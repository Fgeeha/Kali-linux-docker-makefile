# ====== Конфигурация ======
IMAGE        ?= kali-router-audit:latest
CONTAINER    ?= kali-router-audit
REPORTS_DIR  ?= $(PWD)/reports

# IP роутера (замените при необходимости)
ROUTER_IP    ?= 192.168.1.1

# Протоколы и порты для web-панели
HTTP_PORT    ?= 80
HTTPS_PORT   ?= 443

# Скорость masscan (пакетов/с) — не завышайте
MASSCAN_RATE ?= 1000

# Файлы словарей для hydra (можно использовать стандартные из Kali: /usr/share/wordlists)
USERLIST     ?= users.txt          # положите свой файл в ./reports или укажите абсолютный путь
PASSLIST     ?= passwords.txt      # или используйте rockyou.txt внутри контейнера: /usr/share/wordlists/rockyou.txt

# На Linux рекомендуем host-сеть, чтобы сканировать локалку корректно
DOCKER_RUN   ?= docker run --rm -it \
	--name $(CONTAINER) \
	--network host \
	--privileged \
	-v $(REPORTS_DIR):/work/reports \
	$(IMAGE)

# ====== Цели ======
.PHONY: help
help:
	@echo "Цели:"
	@echo "  make build                 - собрать образ"
	@echo "  make shell                 - интерактивная оболочка внутри контейнера"
	@echo "  make scan-quick            - быстрый TCP-скан популярных портов + сервисы"
	@echo "  make scan-full             - полный TCP-скан всех портов + сервисы"
	@echo "  make scan-vuln             - базовые NSE-скрипты уязвимостей (nmap)"
	@echo "  make scan-web              - whatweb + nikto для HTTP/HTTPS панели"
	@echo "  make scan-ssl              - sslscan для 443/tcp"
	@echo "  make scan-upnp             - UPnP/SSDP и инфо по пробросам портов"
	@echo "  make masscan               - быстрый порт-скан masscan (осторожно с rate)"
	@echo "  make hydra-http-basic      - словарная проверка HTTP Basic/Digest (собственное устройство!)"
	@echo "  make hydra-ssh             - словарная проверка SSH (если включён на роутере)"
	@echo "  make all-safe              - пакет безопасных проверок без перебора паролей"
	@echo "Переменные: ROUTER_IP, HTTP_PORT, HTTPS_PORT, MASSCAN_RATE, USERLIST, PASSLIST"

# Сборка
.PHONY: build
build:
	@mkdir -p $(REPORTS_DIR)
	docker build -t $(IMAGE) .

# Оболочка
.PHONY: shell
shell: build
	$(DOCKER_RUN)

# Быстрый скан популярных портов
.PHONY: scan-quick
scan-quick: build
	$(DOCKER_RUN) -c "\
		date > /work/reports/scan-quick.txt && \
		echo '== nmap top-ports on $(ROUTER_IP) ==' >> /work/reports/scan-quick.txt && \
		nmap -Pn -T4 -sS -sV --top-ports 200 $(ROUTER_IP) | tee -a /work/reports/scan-quick.txt \
	"

# Полный скан всех портов
.PHONY: scan-full
scan-full: build
	$(DOCKER_RUN) -c "\
		date > /work/reports/scan-full.txt && \
		echo '== nmap full tcp scan on $(ROUTER_IP) ==' >> /work/reports/scan-full.txt && \
		nmap -Pn -T4 -sS -sV -p- $(ROUTER_IP) | tee -a /work/reports/scan-full.txt \
	"

# Базовые скрипты уязвимостей (могут быть шумными, но безопасные)
.PHONY: scan-vuln
scan-vuln: build
	$(DOCKER_RUN) -c "\
		date > /work/reports/scan-vuln.txt && \
		echo '== nmap --script vuln,vulners on $(ROUTER_IP) ==' >> /work/reports/scan-vuln.txt && \
		nmap -Pn -sV --script vuln,vulners $(ROUTER_IP) | tee -a /work/reports/scan-vuln.txt \
	"

# Web-панель: whatweb + nikto для HTTP/HTTPS
.PHONY: scan-web
scan-web: build
	$(DOCKER_RUN) -c "\
		date > /work/reports/scan-web.txt && \
		echo '== whatweb http://$(ROUTER_IP):$(HTTP_PORT) ==' >> /work/reports/scan-web.txt && \
		whatweb http://$(ROUTER_IP):$(HTTP_PORT) | tee -a /work/reports/scan-web.txt; \
		echo '\n== nikto -h http://$(ROUTER_IP):$(HTTP_PORT) ==' >> /work/reports/scan-web.txt && \
		nikto -host http://$(ROUTER_IP):$(HTTP_PORT) | tee -a /work/reports/scan-web.txt; \
		echo '\n== whatweb https://$(ROUTER_IP):$(HTTPS_PORT) ==' >> /work/reports/scan-web.txt && \
		whatweb https://$(ROUTER_IP):$(HTTPS_PORT) | tee -a /work/reports/scan-web.txt || true; \
		echo '\n== nikto -h https://$(ROUTER_IP):$(HTTPS_PORT) ==' >> /work/reports/scan-web.txt && \
		nikto -host https://$(ROUTER_IP):$(HTTPS_PORT) | tee -a /work/reports/scan-web.txt || true \
	"

# SSL/TLS проверка
.PHONY: scan-ssl
scan-ssl: build
	$(DOCKER_RUN) -c "\
		date > /work/reports/scan-ssl.txt && \
		echo '== sslscan $(ROUTER_IP):$(HTTPS_PORT) ==' >> /work/reports/scan-ssl.txt && \
		sslscan $(ROUTER_IP):$(HTTPS_PORT) | tee -a /work/reports/scan-ssl.txt \
	"

# UPnP/SSDP и пробросы портов
.PHONY: scan-upnp
scan-upnp: build
	$(DOCKER_RUN) -c "\
		date > /work/reports/scan-upnp.txt && \
		echo '== nmap upnp-info on $(ROUTER_IP) ==' >> /work/reports/scan-upnp.txt && \
		nmap -Pn -p 1900 --script upnp-info $(ROUTER_IP) | tee -a /work/reports/scan-upnp.txt; \
		echo '\n== miniupnpc list ==' >> /work/reports/scan-upnp.txt && \
		upnpc -l | tee -a /work/reports/scan-upnp.txt || true \
	"

# Быстрый порт-скан masscan (осторожно с RATE)
.PHONY: masscan
masscan: build
	$(DOCKER_RUN) -c "\
		date > /work/reports/masscan.txt && \
		echo '== masscan $(ROUTER_IP) -p0-65535 --rate $(MASSCAN_RATE) ==' >> /work/reports/masscan.txt && \
		masscan $(ROUTER_IP) -p0-65535 --rate $(MASSCAN_RATE) | tee -a /work/reports/masscan.txt \
	"

# Словарная проверка HTTP Basic/Digest авторизации админ-панели.
# ВАЖНО: только для собственного устройства и с пониманием рисков!
.PHONY: hydra-http-basic
hydra-http-basic: build
	@test -f $(REPORTS_DIR)/$(notdir $(USERLIST)) || echo "[*] Напоминание: положите $(USERLIST) в $(REPORTS_DIR) или укажите абсолютный путь"
	@test -f $(REPORTS_DIR)/$(notdir $(PASSLIST)) || echo "[*] Напоминание: положите $(PASSLIST) в $(REPORTS_DIR) или укажите абсолютный путь"
	$(DOCKER_RUN) -c "\
		UL='$(if $(filter /%,$(USERLIST)),$(USERLIST),/work/reports/$(notdir $(USERLIST)))'; \
		PL='$(if $(filter /%,$(PASSLIST)),$(PASSLIST),/work/reports/$(notdir $(PASSLIST)))'; \
		date > /work/reports/hydra-http.txt; \
		echo '== hydra HTTP auth check on $(ROUTER_IP):$(HTTP_PORT) ==' >> /work/reports/hydra-http.txt; \
		echo 'Users: ' \$${UL} ', Passwords: ' \$${PL} >> /work/reports/hydra-http.txt; \
		# Пример для HTTP Basic/Digest на / (корень). При необходимости замените путь:
		hydra -L \$${UL} -P \$${PL} -s $(HTTP_PORT) -f -e ns -o /work/reports/hydra-http.txt $(ROUTER_IP) http-get / \
	"

# Словарная проверка SSH (если SSH включён на роутере — обычно нет)
.PHONY: hydra-ssh
hydra-ssh: build
	@test -f $(REPORTS_DIR)/$(notdir $(USERLIST)) || echo "[*] Напоминание: положите $(USERLIST) в $(REPORTS_DIR) или укажите абсолютный путь"
	@test -f $(REPORTS_DIR)/$(notdir $(PASSLIST)) || echo "[*] Напоминание: положите $(PASSLIST) в $(REPORTS_DIR) или укажите абсолютный путь"
	$(DOCKER_RUN) -c "\
		UL='$(if $(filter /%,$(USERLIST)),$(USERLIST),/work/reports/$(notdir $(USERLIST)))'; \
		PL='$(if $(filter /%,$(PASSLIST)),$(PASSLIST),/work/reports/$(notdir $(PASSLIST)))'; \
		date > /work/reports/hydra-ssh.txt; \
		echo '== hydra SSH check on $(ROUTER_IP):22 ==' >> /work/reports/hydra-ssh.txt; \
		hydra -L \$${UL} -P \$${PL} -f -o /work/reports/hydra-ssh.txt $(ROUTER_IP) ssh \
	"

# Пакет безопасных проверок без перебора паролей
.PHONY: all-safe
all-safe: scan-quick scan-web scan-ssl scan-upnp scan-vuln
	@echo "Отчёты в: $(REPORTS_DIR)"
