# Makefile для удобного запуска
IMAGE_NAME := vuln-scanner
CONTAINER_NAME := vuln-scanner-run
REPORT_DIR := $(CURDIR)/reports
TARGET ?= http://127.0.0.1:8080

.PHONY: build run shell zap-baseline zap-full nikto nmap scan sqlmap clean

build:
	docker build -t $(IMAGE_NAME) .

run:
	docker run --rm -it \
	  --name $(CONTAINER_NAME) \
	  -e TARGET=$(TARGET) \
	  -v $(REPORT_DIR):/zap/reports \
	  $(IMAGE_NAME)

shell:
	docker run --rm -it \
	  --name $(CONTAINER_NAME) \
	  -e TARGET=$(TARGET) \
	  -v $(REPORT_DIR):/zap/reports \
	  $(IMAGE_NAME) bash

zap-baseline:
	mkdir -p $(REPORT_DIR)
	docker run --rm -it \
	  -e TARGET=$(TARGET) \
	  -v $(REPORT_DIR):/zap/reports \
	  $(IMAGE_NAME) \
	  python3 /zap/zap-baseline.py -t $(TARGET) -r /zap/reports/zap_baseline.html -d

zap-full:
	mkdir -p $(REPORT_DIR)
	docker run --rm -it \
	  -e TARGET=$(TARGET) \
	  -v $(REPORT_DIR):/zap/reports \
	  $(IMAGE_NAME) \
	  python3 /zap/zap-full-scan.py -t $(TARGET) -r /zap/reports/zap_full.html -d

nikto:
	mkdir -p $(REPORT_DIR)
	docker run --rm -it \
	  -e TARGET=$(TARGET) \
	  -v $(REPORT_DIR):/zap/reports \
	  $(IMAGE_NAME) \
	  nikto -h $(TARGET) -o /zap/reports/nikto.html -Format html

nmap:
	mkdir -p $(REPORT_DIR)
	docker run --rm -it --cap-add=NET_RAW --cap-add=NET_ADMIN \
	  -e TARGET=$(TARGET) \
	  -v $(REPORT_DIR):/zap/reports \
	  $(IMAGE_NAME) \
	  bash -lc "nmap -sS -sV -Pn --top-ports 1000 -oA /zap/reports/nmap $(TARGET)"

# sqlmap: example usage
# make sqlmap TARGET="http://example.com/page.php?id=1" SQLMAP=true
sqlmap:
	@mkdir -p $(REPORT_DIR)
	@echo "[*] Running sqlmap in container..."
	docker run --rm -it \
	  --name $(CONTAINER_NAME)-sqlmap \
	  -e TARGET=$(TARGET) \
	  -e SQLMAP=true \
	  -e SQLMAP_OPTS="$(SQLMAP_OPTS)" \
	  -e SQLMAP_DATA="$(SQLMAP_DATA)" \
	  -v $(REPORT_DIR):/zap/reports \
	  $(IMAGE_NAME) \
	  /usr/local/bin/scan.sh

# Полный набор (baseline + full + nikto + nmap; sqlmap off by default)
scan: build
	mkdir -p $(REPORT_DIR)
	docker run --rm -it \
	  --name $(CONTAINER_NAME) \
	  -e TARGET=$(TARGET) \
	  -v $(REPORT_DIR):/zap/reports \
	  $(IMAGE_NAME) \
	  /usr/local/bin/scan.sh

# Полный набор + sqlmap
scan-all: build
	mkdir -p $(REPORT_DIR)
	docker run --rm -it \
	  --name $(CONTAINER_NAME) \
	  -e TARGET=$(TARGET) \
	  -e SQLMAP=true \
	  -e SQLMAP_OPTS="$(SQLMAP_OPTS)" \
	  -e SQLMAP_DATA="$(SQLMAP_DATA)" \
	  -v $(REPORT_DIR):/zap/reports \
	  $(IMAGE_NAME) \
	  /usr/local/bin/scan.sh

clean:
	rm -rf $(REPORT_DIR)/* || true
