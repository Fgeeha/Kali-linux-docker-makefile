# Rolling-образ намеренно не закреплён по версии: сканеру нужны свежие базы
# Nikto/Nmap и свежий zaproxy. Воспроизводимость обеспечивается закреплением
# ZAP_REF и версий pip ниже; для полностью детерминированной сборки
# замените тег на digest.
# hadolint ignore=DL3007
FROM kalilinux/kali-rolling:latest

# Версия официальных скриптов ZAP. Держите её в соответствии с версией
# пакета zaproxy в Kali (на момент написания — 2.17.0).
ARG ZAP_REF=v2.17.0

ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/zap \
    IS_CONTAINERIZED=true

# Инструменты сканирования
# hadolint ignore=DL3008
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        jq \
        openjdk-21-jre \
        zaproxy \
        nikto \
        nmap \
        sqlmap \
        python3 \
        python3-pip \
        python3-setuptools \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Python-клиент ZAP и PyYAML — обязательные зависимости zap-baseline.py
# и zap-full-scan.py (см. docker/requirements.txt в репозитории zaproxy).
RUN pip3 install --no-cache-dir --break-system-packages \
        zaproxy==0.6.0 \
        pyyaml==6.0.3

# Официальные скрипты ZAP. Версия закреплена, сборка воспроизводима.
# Без zap_common.py остальные два скрипта падают на импорте, поэтому он
# качается вместе с ними. Ошибка загрузки должна ломать сборку, а не
# приводить к образу с молча отключённым ZAP.
RUN mkdir -p /opt/zap-scripts \
    && for f in zap_common.py zap-baseline.py zap-full-scan.py; do \
         curl -fsSL -o "/opt/zap-scripts/$f" \
           "https://raw.githubusercontent.com/zaproxy/zaproxy/${ZAP_REF}/docker/$f"; \
       done \
    && chmod +x /opt/zap-scripts/zap-baseline.py /opt/zap-scripts/zap-full-scan.py

# Скрипты ZAP жёстко зашивают путь /zap/zap-x.sh (zap_common.create_start_options).
# В Kali лаунчер лежит в /usr/share/zaproxy/zap.sh; zap.sh корректно
# разыменовывает симлинк и сам вычисляет BASEDIR.
# /zap открыт на запись, чтобы контейнер работал и от непривилегированного
# пользователя (--user): туда пишутся zap.out и ~/.ZAP.
# Запись открыта только на двух каталогах, которые её действительно требуют
# (zap.out, ~/.ZAP и точка монтирования), а не рекурсивно на всём дереве.
RUN mkdir -p /zap/wrk \
    && ln -s /usr/share/zaproxy/zap.sh /zap/zap-x.sh \
    && chmod 1777 /zap /zap/wrk

COPY scan.sh /usr/local/bin/scan.sh
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/scan.sh /usr/local/bin/entrypoint.sh

# /zap/wrk — точка монтирования каталога отчётов и base_dir скриптов ZAP.
WORKDIR /zap

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/usr/local/bin/scan.sh"]
