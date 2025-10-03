# Используем официальный образ OWASP ZAP как базу (включает ZAP)
FROM owasp/zap2docker-stable:2.17.0

USER root

# Устанавливаем дополнительные инструменты: nikto, nmap, curl, xmlstarlet, sqlmap и т.п.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      nikto \
      nmap \
      curl \
      xmlstarlet \
      python3 \
      python3-pip \
      jq \
      sqlmap \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Обновляем pip и ставим пару утилит (опционально)
RUN pip3 install --no-cache-dir requests

# Копируем скрипты
COPY scan.sh /usr/local/bin/scan.sh
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/scan.sh /usr/local/bin/entrypoint.sh

# Рабочая директория
WORKDIR /zap

# Точка входа
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash"]
