# vuln-scanner

Контейнеризированный набор для сканирования веб-приложения на уязвимости.
База образа — `kalilinux/kali-rolling`. Инструменты: OWASP ZAP, Nikto, Nmap, sqlmap.

> ⚠️ **Легальность и ответственность**
> Используйте проект **только** с явного разрешения владельца ресурса.
> Автор не несёт ответственности за неправомерное использование.
> Запуск заблокирован до тех пор, пока вы явно не передадите
> `CONFIRM_AUTHORIZED=yes` — это подтверждение того, что разрешение получено.

## Структура

| Файл | Назначение |
|------|------------|
| `Dockerfile` | Образ на базе Kali с ZAP, Nikto, Nmap, sqlmap и официальными скриптами ZAP |
| `scan.sh` | Оркестратор: последовательный запуск инструментов, сводка, коды возврата |
| `entrypoint.sh` | Точка входа контейнера |
| `Makefile` | Цели запуска (`make help` — список) |
| `reports/` | Каталог отчётов, монтируется в контейнер как `/zap/wrk` |

## Требования

- Docker
- Свободное место под отчёты (полный скан ZAP может дать сотни мегабайт)

## Быстрый старт

```bash
make build
make scan TARGET=http://your-target.example.com CONFIRM_AUTHORIZED=yes
```

Отчёты появятся в `./reports/<YYYYmmdd_HHMMSS>/`, сводка — `index.html` в той же папке.

`make help` покажет все доступные цели.

## Цели Makefile

| Цель | Что делает |
|------|-----------|
| `build` | Собрать образ |
| `scan` (`run`) | ZAP baseline + Nikto + Nmap (набор по умолчанию) |
| `scan-all` | Всё, включая ZAP full scan и sqlmap — долго |
| `baseline` (`zap-baseline`) | Только пассивный скан ZAP |
| `full` (`zap-full`) | Только полный активный скан ZAP |
| `nikto` | Только Nikto |
| `nmap` | Только Nmap |
| `sqlmap` | Только sqlmap |
| `lint` | ShellCheck + Hadolint (запускаются в контейнерах) |
| `test` | Проверки `scan.sh` на заглушках инструментов |
| `check` | `lint` + `test` |
| `shell` | Shell внутри образа |
| `clean` | Очистить `reports/` |

Примеры:

```bash
make baseline TARGET=http://your-target CONFIRM_AUTHORIZED=yes
make nmap     TARGET=example.com        CONFIRM_AUTHORIZED=yes
make sqlmap   TARGET='http://host/item?id=1' CONFIRM_AUTHORIZED=yes \
              SQLMAP_OPTS='--level=3 --risk=2'
```

## Переменные окружения

| Переменная | По умолчанию | Описание |
|-----------|--------------|----------|
| `TARGET` | — | URL или хост цели. Обязательна |
| `CONFIRM_AUTHORIZED` | — | Должна быть `yes`, иначе запуск отклоняется |
| `REPORT_DIR` | `/zap/wrk` | Каталог отчётов внутри контейнера |
| `ZAP_BASELINE` | `true` | Пассивный скан ZAP |
| `ZAP_FULL` | `false` | Активный скан ZAP (может идти часами) |
| `ZAP_OPTS` | — | Доп. опции для скриптов ZAP, например `-m 5` |
| `NIKTO` | `true` | Запускать Nikto |
| `NIKTO_OPTS` | — | Доп. опции Nikto |
| `NMAP` | `true` | Запускать Nmap |
| `NMAP_OPTS` | `-sT -sV -Pn --top-ports 1000` | Опции Nmap |
| `SQLMAP` | `false` | Запускать sqlmap |
| `SQLMAP_OPTS` | — | Доп. опции sqlmap |
| `SQLMAP_DATA` | — | Тело POST-запроса для sqlmap |

### Про `nmap -sT` вместо `-sS`

По умолчанию используется connect-скан (`-sT`): он работает без root и без
дополнительных capabilities, поэтому контейнер запускается от вашего UID и не
оставляет root-овых файлов в `reports/`. SYN-скан (`-sS`) быстрее, но требует
привилегий:

```bash
docker run --rm --cap-add=NET_RAW --cap-add=NET_ADMIN \
  -e TARGET=http://your-target -e CONFIRM_AUTHORIZED=yes \
  -e NMAP_OPTS='-sS -sV -Pn --top-ports 1000' \
  -v "$PWD/reports:/zap/wrk" vuln-scanner-kali scan.sh
```

Такой запуск идёт от root, и файлы отчётов будут принадлежать root.

## Коды возврата `scan.sh`

Пригодны для использования в CI как gate:

| Код | Значение |
|-----|----------|
| `0` | Все инструменты отработали, замечаний нет |
| `1` | Найдены замечания (ZAP вернул FAIL или WARN) |
| `2` | Сбой инструмента или окружения (в т.ч. недоступный каталог отчётов) |
| `3` | Ошибка конфигурации: нет `TARGET` или `CONFIRM_AUTHORIZED` |

Код `3` возвращается только до начала сканирования и означает, что запуск
надо исправить. Всё, что ломается по ходу прогона, даёт `2`: сводка
`index.html` при этом всё равно пишется.

## Формат отчётов

```
reports/20260816_143000/
├── index.html          # сводка по всем инструментам со ссылками
├── zap_baseline.html
├── zap_baseline.json
├── zap_baseline_zap.yaml
├── nikto.htm           # Nikto сам дописывает .htm
├── nmap.nmap / nmap.xml / nmap.gnmap
└── sqlmap/             # если включён
```

## Разработка

```bash
make check   # ShellCheck + Hadolint + тесты scan.sh
```

`test_scan.sh` подменяет ZAP, Nikto, Nmap и sqlmap заглушками на `PATH`,
поэтому запускается за секунду и без Docker. Проверяются коды возврата,
разбор хоста из URL, изоляция прогонов по каталогам и то, что все ссылки
в `index.html` ведут на реально созданные файлы.

То же самое гоняется в CI (`.github/workflows/ci.yml`) вместе со сборкой
образа и проверкой, что скрипты ZAP и их зависимости на месте.

## Версии

Образ закрепляет версию официальных скриптов ZAP через `ARG ZAP_REF`
(по умолчанию `v2.17.0` — совпадает с версией пакета `zaproxy` в Kali).
При обновлении пакета в Kali поднимите и `ZAP_REF`:

```bash
docker build --build-arg ZAP_REF=v2.18.0 -t vuln-scanner-kali .
```

## Лицензия

[MIT](LICENSE).
