#!/usr/bin/env bash
# Проверка логики scan.sh без контейнера: инструменты подменяются заглушками
# на PATH, проверяются коды возврата, разбор хоста и сборка сводки.
set -euo pipefail

SCAN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scan.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

BIN="$WORK/bin"
mkdir -p "$BIN" "$WORK/zap-scripts" "$WORK/reports" "$WORK/zapbase"

fail() { echo "FAIL: $*" >&2; exit 1; }

# --- заглушки инструментов -------------------------------------------------
# Каждая пишет свои аргументы в $WORK/<имя>.args и создаёт файл отчёта,
# код возврата берётся из $WORK/<имя>.rc (по умолчанию 0).

# nikto: всегда дописывает .htm к значению -o (проверено на реальном nikto 2.6.0)
cat >"$BIN/nikto" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$WORK/nikto.args"
prev=""
for a in "\$@"; do
  [ "\$prev" = "-o" ] && : > "\$a.htm"
  prev="\$a"
done
exit \$(cat "$WORK/nikto.rc" 2>/dev/null || echo 0)
STUB

# nmap: -oA даёт три файла с расширениями
cat >"$BIN/nmap" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$WORK/nmap.args"
prev=""
for a in "\$@"; do
  if [ "\$prev" = "-oA" ]; then for e in nmap xml gnmap; do : > "\$a.\$e"; done; fi
  prev="\$a"
done
exit \$(cat "$WORK/nmap.rc" 2>/dev/null || echo 0)
STUB

cat >"$BIN/sqlmap" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$WORK/sqlmap.args"
exit \$(cat "$WORK/sqlmap.rc" 2>/dev/null || echo 0)
STUB

# python3 ведёт себя как скрипт ZAP в докер-режиме: игнорирует любой путь
# в -r/-J и пишет отчёты по basename в свой base_dir.
cat >"$BIN/python3" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$WORK/zap.args"
prev=""
for a in "\$@"; do
  case "\$prev" in -r|-J) : > "$WORK/zapbase/\$(basename "\$a")" ;; esac
  prev="\$a"
done
: > "$WORK/zapbase/zap.yaml"
exit \$(cat "$WORK/zap.rc" 2>/dev/null || echo 0)
STUB

chmod +x "$BIN"/nikto "$BIN"/nmap "$BIN"/sqlmap "$BIN"/python3

: > "$WORK/zap-scripts/zap-baseline.py"
: > "$WORK/zap-scripts/zap-full-scan.py"

export PATH="$BIN:$PATH"
export REPORT_DIR="$WORK/reports"
export ZAP_SCRIPTS_DIR="$WORK/zap-scripts"
export ZAP_BASE_DIR="$WORK/zapbase"

# run_scan [VAR=VAL ...] -> печатает код возврата, не падая.
# Переменные передаются через env, а не префиксом перед вызовом: для функции
# bash оставляет такое присваивание в текущей оболочке, и оно протекает
# в следующие проверки.
run_scan() {
  local rc=0
  ( env "$@" "$SCAN" >"$WORK/out.log" 2>&1 ) || rc=$?
  echo "$rc"
}

latest_report_dir() {
  find "$REPORT_DIR" -mindepth 1 -maxdepth 1 -type d | sort | tail -1
}

# --- 1. без TARGET — код 3 -------------------------------------------------
rc="$(run_scan TARGET= CONFIRM_AUTHORIZED=yes)"
[ "$rc" = 3 ] || fail "без TARGET ожидался код 3, получен $rc"
grep -q 'TARGET пуст' "$WORK/out.log" || fail "нет сообщения про пустой TARGET"

# --- 2. без подтверждения — код 3 ------------------------------------------
# Сообщение проверяется явно: без этого тест прошёл бы и на ветке TARGET,
# которая возвращает тот же код 3.
for confirm in '' no YES 1; do
  rc="$(run_scan TARGET=http://example.com "CONFIRM_AUTHORIZED=$confirm")"
  [ "$rc" = 3 ] || fail "CONFIRM_AUTHORIZED='$confirm': ожидался код 3, получен $rc"
  grep -q 'разрешения владельца' "$WORK/out.log" \
    || fail "CONFIRM_AUTHORIZED='$confirm': сработала не та проверка"
done

# --- 2a. сбой окружения — код 2, а не 3 ------------------------------------
# Неписуемый каталог отчётов это не ошибка конфигурации: CI должен видеть
# разницу между забытым TARGET и неподмонтированным томом.
RO="$WORK/readonly"; mkdir -p "$RO"; chmod 0555 "$RO"
rc="$(run_scan TARGET=http://example.com CONFIRM_AUTHORIZED=yes "REPORT_DIR=$RO/sub")"
chmod 0755 "$RO"
[ "$rc" = 2 ] || fail "неписуемый REPORT_DIR: ожидался код 2, получен $rc"

# --- 3. чистый прогон — код 0, есть index.html -----------------------------
export TARGET='http://user:pw@example.com:8080/app/path?a=1'
export CONFIRM_AUTHORIZED=yes
rc="$(run_scan)"
[ "$rc" = 0 ] || fail "чистый прогон: ожидался код 0, получен $rc (см. $WORK/out.log)"

DIR="$(latest_report_dir)"
[ -f "$DIR/index.html" ] || fail "не создан index.html"
grep -q 'ZAP baseline' "$DIR/index.html" || fail "index.html без строки ZAP baseline"

# --- 3a. отчёты ZAP перенесены из base_dir в каталог прогона ---------------
for f in zap_baseline.html zap_baseline.json; do
  [ -f "$DIR/$f" ] || fail "отчёт ZAP $f не перенесён в каталог прогона"
done
[ -z "$(ls -A "$WORK/zapbase")" ] || fail "в base_dir ZAP остались файлы: $(ls "$WORK/zapbase")"

# --- 3b. отчёт Nikto лежит там, где на него ссылается сводка ---------------
[ -f "$DIR/nikto.htm" ] || fail "не создан nikto.htm (Nikto дописывает .htm к -o)"

# --- 3c. у каждого отработавшего инструмента в сводке есть живая ссылка -----
# Проверять «все ссылки ведут на существующий файл» бессмысленно: scan.sh
# и так печатает <a> только для существующего файла, такая проверка не может
# упасть. Падать должно обратное — инструмент отработал, а ссылки нет.
for tool in 'ZAP baseline' 'Nikto' 'Nmap'; do
  row="$(grep -F "<td>$tool</td>" "$DIR/index.html" || true)"
  [ -n "$row" ] || fail "в index.html нет строки '$tool'"
  case "$row" in
    *'<a href='*) ;;
    *) fail "'$tool' отработал, но в сводке нет ссылки на отчёт: $row" ;;
  esac
done
# и сам файл, на который ведёт ссылка, на месте.
# Подстановка процесса, а не конвейер: в конвейере цикл ушёл бы в подоболочку
# и exit из fail не остановил бы скрипт.
while read -r l; do
  [ -n "$l" ] || continue
  [ -e "$DIR/$l" ] || fail "битая ссылка в index.html: $l"
done < <(grep -o 'href="[^"]*"' "$DIR/index.html" | sed 's/href="//; s/"$//')

# --- 4. хост извлечён без схемы, credentials, порта и пути -----------------
grep -qx 'example.com' "$WORK/nmap.args" \
  || fail "nmap получил неверный хост: $(tr '\n' ' ' <"$WORK/nmap.args")"

# --- 4a. разбор хоста: IPv6, query без пути, fragment ----------------------
check_host() { # check_host <TARGET> <ожидаемый хост>
  run_scan "TARGET=$1" CONFIRM_AUTHORIZED=yes ZAP_BASELINE=false NIKTO=false >/dev/null
  grep -qx "$2" "$WORK/nmap.args" \
    || fail "из '$1' ожидался хост '$2', nmap получил: $(tr '\n' ' ' <"$WORK/nmap.args")"
}
check_host 'http://example.com?a=1'      'example.com'
check_host 'http://example.com#frag'     'example.com'
check_host 'https://example.com:8443'    'example.com'
check_host '1.2.3.4'                     '1.2.3.4'
check_host 'http://[2001:db8::1]:8080/x' '2001:db8::1'
grep -qx -- '-6' "$WORK/nmap.args" || fail "для IPv6-цели не передан флаг -6"

# --- 4a. ZAP получает имя файла, а не путь (иначе отчёт теряется) ----------
grep -qx 'zap_baseline.html' "$WORK/zap.args" \
  || fail "в -r передан не basename: $(tr '\n' ' ' <"$WORK/zap.args")"

# --- 5. sqlmap и ZAP full по умолчанию выключены ---------------------------
[ ! -f "$WORK/sqlmap.args" ] || fail "sqlmap запустился, хотя SQLMAP=false"
grep -q 'zap-baseline.py' "$WORK/zap.args" || fail "не запущен zap-baseline.py"
grep -q 'zap-full-scan.py' "$WORK/zap.args" && fail "zap-full-scan.py запустился при ZAP_FULL=false"

# --- 6. находки ZAP (rc=1,2) -> код 1 --------------------------------------
for zaprc in 1 2; do
  echo "$zaprc" > "$WORK/zap.rc"
  rc="$(run_scan)"
  [ "$rc" = 1 ] || fail "ZAP rc=$zaprc: ожидался код 1, получен $rc"
done

# --- 7. сбой ZAP (rc>=3) -> код 2 ------------------------------------------
echo 3 > "$WORK/zap.rc"
rc="$(run_scan)"
[ "$rc" = 2 ] || fail "ZAP rc=3: ожидался код 2, получен $rc"
rm -f "$WORK/zap.rc"

# --- 8. сбой Nikto -> код 2 ------------------------------------------------
echo 1 > "$WORK/nikto.rc"
rc="$(run_scan)"
[ "$rc" = 2 ] || fail "сбой Nikto: ожидался код 2, получен $rc"
rm -f "$WORK/nikto.rc"

# --- 9. отсутствие скрипта ZAP -> код 2, а не тихий пропуск ----------------
mv "$WORK/zap-scripts/zap-baseline.py" "$WORK/zap-scripts/hidden.py"
rc="$(run_scan)"
[ "$rc" = 2 ] || fail "нет zap-baseline.py: ожидался код 2, получен $rc"
mv "$WORK/zap-scripts/hidden.py" "$WORK/zap-scripts/zap-baseline.py"

# --- 10. sqlmap включается флагом, --data не разрывается по пробелам -------
rm -f "$WORK/sqlmap.args"
run_scan SQLMAP=true ZAP_BASELINE=false NIKTO=false NMAP=false \
  'SQLMAP_DATA=user=a b&pw=c' 'SQLMAP_OPTS=--level=3 --risk=2' >/dev/null
[ -f "$WORK/sqlmap.args" ] || fail "sqlmap не запустился при SQLMAP=true"
grep -qx 'user=a b&pw=c' "$WORK/sqlmap.args" \
  || fail "SQLMAP_DATA разорван по пробелу: $(tr '\n' '|' <"$WORK/sqlmap.args")"
grep -qx -- '--level=3' "$WORK/sqlmap.args" \
  || fail "SQLMAP_OPTS не разбит на отдельные опции"

# --- 11. каждый прогон — свой каталог --------------------------------------
runs="$(find "$REPORT_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l)"
[ "$runs" -ge 2 ] || fail "прогоны не разложены по отдельным каталогам ($runs)"

echo "OK: все проверки scan.sh пройдены"
