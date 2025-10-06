IMAGE_NAME := vuln-scanner-kali
CONTAINER_NAME := vuln-scanner-kali-run
REPORT_DIR := $(CURDIR)/reports
TARGET ?= http://127.0.0.1:8080
BASIC_AUTH_USER ?=
BASIC_AUTH_PASS ?=

.PHONY: build run shell zap-baseline zap-full nikto nmap scan sqlmap scan-all clean

build:
	docker build -t $(IMAGE_NAME) .

run:
	mkdir -p $(REPORT_DIR)
        docker run --rm -it \
          --name $(CONTAINER_NAME) \
          -e TARGET=$(TARGET) \
          -e BASIC_AUTH_USER="$(BASIC_AUTH_USER)" \
          -e BASIC_AUTH_PASS="$(BASIC_AUTH_PASS)" \
          -v $(REPORT_DIR):/zap/reports \
          $(IMAGE_NAME)

shell:
	mkdir -p $(REPORT_DIR)
        docker run --rm -it \
          --name $(CONTAINER_NAME) \
          -e TARGET=$(TARGET) \
          -e BASIC_AUTH_USER="$(BASIC_AUTH_USER)" \
          -e BASIC_AUTH_PASS="$(BASIC_AUTH_PASS)" \
          -v $(REPORT_DIR):/zap/reports \
          $(IMAGE_NAME) bash

# Запуск ZAP baseline напрямую (если скрипты скачаны)
zap-baseline:
	mkdir -p $(REPORT_DIR)
        docker run --rm -it \
          -e TARGET=$(TARGET) \
          -e BASIC_AUTH_USER="$(BASIC_AUTH_USER)" \
          -e BASIC_AUTH_PASS="$(BASIC_AUTH_PASS)" \
          -v $(REPORT_DIR):/zap/reports \
          $(IMAGE_NAME) \
          bash -lc "python3 /opt/zap-scripts/zap-baseline.py -t $(TARGET) -r /zap/reports/zap_baseline.html -d || true"

zap-full:
	mkdir -p $(REPORT_DIR)
        docker run --rm -it \
          -e TARGET=$(TARGET) \
          -e BASIC_AUTH_USER="$(BASIC_AUTH_USER)" \
          -e BASIC_AUTH_PASS="$(BASIC_AUTH_PASS)" \
          -v $(REPORT_DIR):/zap/reports \
          $(IMAGE_NAME) \
          bash -lc "python3 /opt/zap-scripts/zap-full-scan.py -t $(TARGET) -r /zap/reports/zap_full.html -d || true"

nikto:
	mkdir -p $(REPORT_DIR)
        docker run --rm -it \
          -e TARGET=$(TARGET) \
          -e BASIC_AUTH_USER="$(BASIC_AUTH_USER)" \
          -e BASIC_AUTH_PASS="$(BASIC_AUTH_PASS)" \
          -v $(REPORT_DIR):/zap/reports \
          $(IMAGE_NAME) \
          nikto -h $(TARGET) -o /zap/reports/nikto.html -Format html

nmap:
	mkdir -p $(REPORT_DIR)
        docker run --rm -it --cap-add=NET_RAW --cap-add=NET_ADMIN \
          -e TARGET=$(TARGET) \
          -e BASIC_AUTH_USER="$(BASIC_AUTH_USER)" \
          -e BASIC_AUTH_PASS="$(BASIC_AUTH_PASS)" \
          -v $(REPORT_DIR):/zap/reports \
          $(IMAGE_NAME) \
          bash -lc "nmap -sS -sV -Pn --top-ports 1000 -oA /zap/reports/nmap $(shell echo $(TARGET) | sed -E 's#^https?://##' | sed -E 's#/.*$$//')"

sqlmap:
	@mkdir -p $(REPORT_DIR)
	@echo "[*] Running sqlmap in container..."
        docker run --rm -it \
          --name $(CONTAINER_NAME)-sqlmap \
          -e TARGET=$(TARGET) \
          -e SQLMAP=true \
          -e SQLMAP_OPTS="$(SQLMAP_OPTS)" \
          -e SQLMAP_DATA="$(SQLMAP_DATA)" \
          -e BASIC_AUTH_USER="$(BASIC_AUTH_USER)" \
          -e BASIC_AUTH_PASS="$(BASIC_AUTH_PASS)" \
          -v $(REPORT_DIR):/zap/reports \
          $(IMAGE_NAME) \
          /usr/local/bin/scan.sh

scan: build
	mkdir -p $(REPORT_DIR)
        docker run --rm -it \
          --name $(CONTAINER_NAME) \
          -e TARGET=$(TARGET) \
          -e BASIC_AUTH_USER="$(BASIC_AUTH_USER)" \
          -e BASIC_AUTH_PASS="$(BASIC_AUTH_PASS)" \
          -v $(REPORT_DIR):/zap/reports \
          $(IMAGE_NAME) \
          /usr/local/bin/scan.sh

# Включая sqlmap
scan-all: build
	mkdir -p $(REPORT_DIR)
        docker run --rm -it \
          --name $(CONTAINER_NAME) \
          -e TARGET=$(TARGET) \
          -e SQLMAP=true \
          -e SQLMAP_OPTS="$(SQLMAP_OPTS)" \
          -e SQLMAP_DATA="$(SQLMAP_DATA)" \
          -e BASIC_AUTH_USER="$(BASIC_AUTH_USER)" \
          -e BASIC_AUTH_PASS="$(BASIC_AUTH_PASS)" \
          -v $(REPORT_DIR):/zap/reports \
          $(IMAGE_NAME) \
          /usr/local/bin/scan.sh

clean:
	rm -rf $(REPORT_DIR)/* || true
