FROM kalilinux/kali-rolling

ENV DEBIAN_FRONTEND=noninteractive

USER root

# Обновляем и ставим инструменты
RUN apt-get update && apt-get install -y --no-install-recommends \
    openjdk-21-jre \
    zaproxy \
    nikto \
    nmap \
    sqlmap \
    curl \
    jq \
    python3 \
    python3-pip \
    xmlstarlet \
    git \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# pip utils (optional)
RUN pip3 install --no-cache-dir --break-system-packages requests


# Загружаем официальные скрипты ZAP (zap-baseline.py, zap-full-scan.py) в /opt/zap-scripts
# Эти скрипты используются ниже; если URL изменится, замените их на актуальные.
RUN mkdir -p /opt/zap-scripts && \
    curl -fsSL -o /opt/zap-scripts/zap-baseline.py \
    https://raw.githubusercontent.com/zaproxy/zaproxy/main/docker/zap-baseline.py || true && \
    curl -fsSL -o /opt/zap-scripts/zap-full-scan.py \
    https://raw.githubusercontent.com/zaproxy/zaproxy/main/docker/zap-full-scan.py || true && \
    chmod +x /opt/zap-scripts/*.py || true

# Копируем скрипты управления (scan/entrypoint)
COPY scan.sh /usr/local/bin/scan.sh
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/scan.sh /usr/local/bin/entrypoint.sh

WORKDIR /zap

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash"]
