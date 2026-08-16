#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# Параметры (задаются через env или через make)
# ---------------------------------------------------------------------------
TARGET="${TARGET:-}"
REPORT_DIR="${REPORT_DIR:-/zap/wrk}"
ZAP_SCRIPTS_DIR="${ZAP_SCRIPTS_DIR:-/opt/zap-scripts}"
# Скрипты ZAP в докер-режиме жёстко пишут отчёты сюда (zap_common: base_dir),
# независимо от REPORT_DIR. Отсюда файлы переносятся в каталог прогона.
ZAP_BASE_DIR="${ZAP_BASE_DIR:-/zap/wrk}"

# Подтверждение прав на сканирование. Без него запуск запрещён.
CONFIRM_AUTHORIZED="${CONFIRM_AUTHORIZED:-}"

ZAP_BASELINE="${ZAP_BASELINE:-true}"   # быстрый пассивный скан ZAP
ZAP_FULL="${ZAP_FULL:-false}"          # полный активный скан ZAP (долго)
ZAP_OPTS="${ZAP_OPTS:-}"               # доп. опции для скриптов ZAP
NIKTO="${NIKTO:-true}"
NIKTO_OPTS="${NIKTO_OPTS:-}"
NMAP="${NMAP:-true}"
# -sT (connect scan) работает без root и без NET_RAW. Для -sS нужен
# запуск от root с --cap-add=NET_RAW --cap-add=NET_ADMIN.
NMAP_OPTS="${NMAP_OPTS:--sT -sV -Pn --top-ports 1000}"
SQLMAP="${SQLMAP:-false}"
SQLMAP_OPTS="${SQLMAP_OPTS:-}"
SQLMAP_DATA="${SQLMAP_DATA:-}"         # тело POST-запроса, если нужно

# ---------------------------------------------------------------------------
# Служебные функции
# ---------------------------------------------------------------------------
# die <код> <сообщение>. Код различает ошибку конфигурации (3) и сбой
# окружения (2) — иначе CI не отличит забытый TARGET от неподмонтированного тома.
die() { local code="$1"; shift; echo "ERROR: $*" >&2; exit "$code"; }

FAILED=0    # хотя бы один инструмент завершился ошибкой
FINDINGS=0  # хотя бы один инструмент нашёл замечания
SUMMARY=()  # строки "инструмент|статус|файл отчёта"

note() { # note <инструмент> <статус> [файл]
  SUMMARY+=("$1|$2|${3:-}")
  echo "[=] $1: $2"
}

esc() { # экранирование для вставки в HTML
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

# host из URL: убираем схему, credentials, порт, путь, query и fragment.
# Без sed — bash сам умеет. Отдельно разбирается IPv6-литерал в скобках,
# иначе обрезание по первому ':' превращает [::1]:8080 в '['.
target_host() {
  local h="${1#*://}"
  h="${h%%[/?#]*}"
  h="${h##*@}"
  case "$h" in
    \[*\]*) h="${h%%\]*}"; h="${h#\[}" ;;
    *)      h="${h%%:*}" ;;
  esac
  printf '%s' "$h"
}

# run_tool <ярлык> <файл отчёта> -- <команда...>
# Общая обвязка для инструментов без собственных кодов находок:
# 0 — отработал, любой другой код — сбой.
run_tool() {
  local label="$1" report="$2" rc=0
  shift 3   # ярлык, отчёт и разделитель --
  echo "[*] $label ..."
  "$@" || rc=$?
  if [ "$rc" -eq 0 ]; then
    note "$label" "выполнен" "$report"
  else
    note "$label" "ОШИБКА (rc=$rc)" "$report"
    FAILED=1
  fi
}

# ---------------------------------------------------------------------------
# Проверки перед запуском
# ---------------------------------------------------------------------------
[ -n "$TARGET" ] || die 3 "TARGET пуст. Пример: TARGET=http://example.com"

if [ "$CONFIRM_AUTHORIZED" != "yes" ]; then
  die 3 "сканирование допустимо только с разрешения владельца ресурса.
       Подтвердите: CONFIRM_AUTHORIZED=yes"
fi

mkdir -p "$REPORT_DIR" \
  || die 2 "не удалось создать $REPORT_DIR (проверьте права на смонтированный том)"

# Каталог на каждый прогон. Метка времени с точностью до секунды, поэтому
# при совпадении добавляется суффикс — иначе два прогона затрут друг друга.
RUN_ID="$(date +%Y%m%d_%H%M%S)"
OUT="$REPORT_DIR/$RUN_ID"
n=1
while ! mkdir "$OUT" 2>/dev/null; do
  [ -e "$OUT" ] || die 2 "не удалось создать $OUT"
  RUN_ID="$(date +%Y%m%d_%H%M%S)_$n"
  OUT="$REPORT_DIR/$RUN_ID"
  n=$((n + 1))
done

echo "[*] Цель:     $TARGET"
echo "[*] Отчёты:   $OUT"
echo

# ---------------------------------------------------------------------------
# 1) ZAP baseline — пассивный скан
# ---------------------------------------------------------------------------
run_zap() { # run_zap <имя> <скрипт> <префикс файлов>
  local label="$1" script="$2" prefix="$3" rc=0

  if [ ! -f "$ZAP_SCRIPTS_DIR/$script" ]; then
    note "$label" "ПРОПУЩЕН — $script не найден в $ZAP_SCRIPTS_DIR"
    FAILED=1
    return
  fi

  echo "[*] $label ..."
  # Отчёты задаются ТОЛЬКО именем файла: Automation Framework внутри ZAP
  # принимает reportDir и reportFile раздельно, и абсолютный путь в -r/-J
  # приводит к молчаливой потере отчёта.
  # ZAP_OPTS намеренно без кавычек: это список опций.
  # shellcheck disable=SC2086
  python3 "$ZAP_SCRIPTS_DIR/$script" \
    -t "$TARGET" \
    -r "${prefix}.html" \
    -J "${prefix}.json" \
    $ZAP_OPTS || rc=$?

  # Переносим то, что ZAP написал в base_dir, в каталог текущего прогона.
  local f
  for f in "${prefix}.html" "${prefix}.json"; do
    if [ -f "$ZAP_BASE_DIR/$f" ]; then
      mv -f "$ZAP_BASE_DIR/$f" "$OUT/$f"
    fi
  done
  # zap.yaml пишется под одним именем обоими скриптами, поэтому переносится
  # с префиксом — иначе full scan затирает конфиг baseline.
  if [ -f "$ZAP_BASE_DIR/zap.yaml" ]; then
    mv -f "$ZAP_BASE_DIR/zap.yaml" "$OUT/${prefix}_zap.yaml"
  fi

  # Коды возврата скриптов ZAP: 0 — чисто, 1 — есть FAIL, 2 — есть WARN,
  # всё остальное — сбой самого сканера.
  case "$rc" in
    0) note "$label" "чисто" "${prefix}.html" ;;
    1) note "$label" "найдены проблемы (FAIL)" "${prefix}.html"; FINDINGS=1 ;;
    2) note "$label" "найдены замечания (WARN)" "${prefix}.html"; FINDINGS=1 ;;
    *) note "$label" "ОШИБКА (rc=$rc)" "${prefix}.html"; FAILED=1 ;;
  esac
}

if [ "$ZAP_BASELINE" = "true" ]; then
  run_zap "ZAP baseline" "zap-baseline.py" "zap_baseline"
else
  note "ZAP baseline" "выключен (ZAP_BASELINE=false)"
fi

# ---------------------------------------------------------------------------
# 2) ZAP full scan — активный скан, выключен по умолчанию (может идти часами)
# ---------------------------------------------------------------------------
if [ "$ZAP_FULL" = "true" ]; then
  run_zap "ZAP full scan" "zap-full-scan.py" "zap_full"
else
  note "ZAP full scan" "выключен (ZAP_FULL=true — включить)"
fi

# ---------------------------------------------------------------------------
# 3) Nikto
# ---------------------------------------------------------------------------
if [ "$NIKTO" = "true" ]; then
  # Nikto всегда дописывает расширение формата к -o, поэтому имя без него:
  # результат окажется в nikto.htm.
  # NIKTO_OPTS намеренно без кавычек: это список опций.
  # shellcheck disable=SC2086
  run_tool "Nikto" "nikto.htm" -- \
    nikto -h "$TARGET" -o "$OUT/nikto" -Format html $NIKTO_OPTS
else
  note "Nikto" "выключен (NIKTO=false)"
fi

# ---------------------------------------------------------------------------
# 4) Nmap
# ---------------------------------------------------------------------------
if [ "$NMAP" = "true" ]; then
  NMAP_TARGET="$(target_host "$TARGET")"
  if [ -z "$NMAP_TARGET" ]; then
    # Не обрываем прогон: остальные инструменты уже отработали и сводка
    # должна быть записана. Это сбой шага, а не ошибка конфигурации.
    note "Nmap" "ОШИБКА — не удалось извлечь хост из '$TARGET'"
    FAILED=1
  else
    # IPv6-литерал требует явного -6, иначе nmap не резолвит адрес.
    NMAP_FAMILY=()
    case "$NMAP_TARGET" in *:*) NMAP_FAMILY=(-6) ;; esac
    # NMAP_OPTS намеренно без кавычек: это список опций.
    # shellcheck disable=SC2086
    run_tool "Nmap" "nmap.nmap" -- \
      nmap $NMAP_OPTS "${NMAP_FAMILY[@]}" -oA "$OUT/nmap" "$NMAP_TARGET"
  fi
else
  note "Nmap" "выключен (NMAP=false)"
fi

# ---------------------------------------------------------------------------
# 5) sqlmap — выключен по умолчанию
# ---------------------------------------------------------------------------
if [ "$SQLMAP" = "true" ]; then
  SQLMAP_OUT="$OUT/sqlmap"
  mkdir -p "$SQLMAP_OUT"
  # Аргументы собираются массивом: --data может содержать пробелы, а
  # SQLMAP_OPTS, наоборот, должен разбиваться на слова.
  SQLMAP_ARGS=(-u "$TARGET" --batch "--output-dir=$SQLMAP_OUT")
  # Не `[ … ] && …`: под set -e ложное условие уронило бы скрипт.
  if [ -n "$SQLMAP_DATA" ]; then
    SQLMAP_ARGS+=(--data "$SQLMAP_DATA")
  fi
  # shellcheck disable=SC2206
  SQLMAP_ARGS+=($SQLMAP_OPTS)
  run_tool "sqlmap" "sqlmap/" -- sqlmap "${SQLMAP_ARGS[@]}"
else
  note "sqlmap" "выключен (SQLMAP=true — включить)"
fi

# ---------------------------------------------------------------------------
# Сводка: index.html + вывод в консоль
# ---------------------------------------------------------------------------
{
  echo '<!doctype html><html lang="ru"><meta charset="utf-8">'
  echo "<title>vuln-scanner — $(esc "$RUN_ID")</title>"
  echo '<style>body{font:14px/1.5 system-ui,sans-serif;margin:2rem;max-width:60rem}
table{border-collapse:collapse;width:100%}th,td{border:1px solid #ccc;padding:.4rem .6rem;text-align:left}
th{background:#f4f4f4}code{background:#f4f4f4;padding:.1rem .3rem}</style>'
  echo "<h1>Отчёт сканирования</h1>"
  echo "<p>Цель: <code>$(esc "$TARGET")</code><br>Запуск: <code>$(esc "$RUN_ID")</code></p>"
  echo '<table><tr><th>Инструмент</th><th>Статус</th><th>Отчёт</th></tr>'
  for row in "${SUMMARY[@]}"; do
    IFS='|' read -r tool status file <<<"$row"
    printf '<tr><td>%s</td><td>%s</td><td>' "$(esc "$tool")" "$(esc "$status")"
    if [ -n "$file" ] && [ -e "$OUT/$file" ]; then
      printf '<a href="%s">%s</a>' "$(esc "$file")" "$(esc "$file")"
    else
      printf '&mdash;'
    fi
    printf '</td></tr>\n'
  done
  echo '</table>'
} > "$OUT/index.html"

echo
echo "[*] Сканирование завершено. Сводка: $OUT/index.html"

# 0 — всё чисто, 1 — есть находки, 2 — сбой инструмента
if [ "$FAILED" -eq 1 ]; then
  exit 2
elif [ "$FINDINGS" -eq 1 ]; then
  exit 1
fi
exit 0
