.DEFAULT_GOAL := help

.PHONY: help build run scan scan-all baseline zap-baseline full zap-full \
        nikto nmap sqlmap lint test check shell clean

IMAGE_NAME := vuln-scanner-kali
REPORT_DIR := $(CURDIR)/reports

TARGET ?= http://127.0.0.1:8080

# Подтверждение прав на сканирование. Без CONFIRM_AUTHORIZED=yes scan.sh
# откажется работать — это осознанный барьер, а не забытый дефолт.
CONFIRM_AUTHORIZED ?=

# Опции инструментов (пробрасываются в контейнер как есть)
ZAP_OPTS ?=
NIKTO_OPTS ?=
NMAP_OPTS ?=
SQLMAP_OPTS ?=
SQLMAP_DATA ?=

# -it только при интерактивном запуске, иначе ломается вызов из CI
TTY := $(shell [ -t 0 ] && echo -it)
UIDGID := $(shell id -u):$(shell id -g)

# Отчёты пишутся в /zap/wrk: это же base_dir официальных скриптов ZAP.
# --user не даёт контейнеру оставить root-овые файлы в примонтированном
# каталоге отчётов на хосте.
DOCKER_RUN = docker run --rm $(TTY) \
	  --user $(UIDGID) \
	  -e TARGET="$(TARGET)" \
	  -e CONFIRM_AUTHORIZED="$(CONFIRM_AUTHORIZED)" \
	  -e ZAP_OPTS="$(ZAP_OPTS)" \
	  -e NIKTO_OPTS="$(NIKTO_OPTS)" \
	  -e NMAP_OPTS="$(NMAP_OPTS)" \
	  -e SQLMAP_OPTS="$(SQLMAP_OPTS)" \
	  -e SQLMAP_DATA="$(SQLMAP_DATA)" \
	  -v $(REPORT_DIR):/zap/wrk

# Выключает все инструменты разом: одиночные цели ниже включают обратно
# только свой, чтобы набор флагов не расходился от цели к цели.
NONE = -e ZAP_BASELINE=false -e ZAP_FULL=false -e NIKTO=false -e NMAP=false -e SQLMAP=false

help: ## Показать список целей
	@grep -hE '^[a-zA-Z0-9_-]+:.*## ' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

# --- Сборка ----------------------------------------------------------------

build: ## Собрать образ сканера
	docker build -t $(IMAGE_NAME) .

# --- Сканирование ----------------------------------------------------------

$(REPORT_DIR):
	@mkdir -p $(REPORT_DIR)

scan: build | $(REPORT_DIR) ## Полный набор по умолчанию: ZAP baseline + Nikto + Nmap
	$(DOCKER_RUN) $(IMAGE_NAME) scan.sh

run: scan ## Синоним scan (сохранён для совместимости)

scan-all: build | $(REPORT_DIR) ## Всё сразу, включая ZAP full scan и sqlmap (долго)
	$(DOCKER_RUN) -e ZAP_FULL=true -e SQLMAP=true $(IMAGE_NAME) scan.sh

baseline: build | $(REPORT_DIR) ## Только пассивный скан ZAP
	$(DOCKER_RUN) $(NONE) -e ZAP_BASELINE=true $(IMAGE_NAME) scan.sh

zap-baseline: baseline ## Синоним baseline (сохранён для совместимости)

full: build | $(REPORT_DIR) ## Только полный активный скан ZAP
	$(DOCKER_RUN) $(NONE) -e ZAP_FULL=true $(IMAGE_NAME) scan.sh

zap-full: full ## Синоним full (сохранён для совместимости)

nikto: build | $(REPORT_DIR) ## Только Nikto
	$(DOCKER_RUN) $(NONE) -e NIKTO=true $(IMAGE_NAME) scan.sh

nmap: build | $(REPORT_DIR) ## Только Nmap
	$(DOCKER_RUN) $(NONE) -e NMAP=true $(IMAGE_NAME) scan.sh

sqlmap: build | $(REPORT_DIR) ## Только sqlmap
	$(DOCKER_RUN) $(NONE) -e SQLMAP=true $(IMAGE_NAME) scan.sh

# --- Проверка --------------------------------------------------------------

lint: ## Проверить shell-скрипты и Dockerfile линтерами
	docker run --rm -v $(CURDIR):/mnt:ro -w /mnt koalaman/shellcheck-alpine:stable \
	  shellcheck scan.sh entrypoint.sh test_scan.sh
	docker run --rm -i hadolint/hadolint < Dockerfile

test: ## Прогнать проверки scan.sh на заглушках инструментов
	./test_scan.sh

check: lint test ## lint + test

# --- Обслуживание ----------------------------------------------------------

shell: build ## Открыть shell внутри контейнера
	@mkdir -p $(REPORT_DIR)
	$(DOCKER_RUN) --name $(CONTAINER_NAME)-shell $(IMAGE_NAME) bash

clean: ## Удалить содержимое каталога отчётов
	rm -rf $(REPORT_DIR)/*
