#!/usr/bin/env bash
set -euo pipefail

# Параметры (можно задавать через env или через make)
TARGET="${TARGET:-}"
REPORT_DIR="${REPORT_DIR:-/zap/reports}"
ZAP_SCRIPTS_DIR="${ZAP_SCRIPTS_DIR:-/opt/zap-scripts}"
ZAP_CMD="${ZAP_CMD:-/usr/bin/zaproxy}"
SQLMAP_OPTS="${SQLMAP_OPTS:-}"   # дополнительные опции для sqlmap
SQLMAP_DATA="${SQLMAP_DATA:-}"   # data for POST (если нужен)
SQLMAP="${SQLMAP:-false}"        # включение sqlmap

if [ -z "$TARGET" ]; then
  echo "ERROR: TARGET is empty. Set TARGET=http://example.com"
  exit 2
fi

mkdir -p "$REPORT_DIR"

timestamp() { date +%Y%m%d_%H%M%S; }

echo "[*] Target: $TARGET"
echo "[*] Reports folder: $REPORT_DIR"

# ---- 1) ZAP baseline (headless) ----
BASELINE_HTML="$REPORT_DIR/zap_baseline_$(timestamp).html"
if [ -x "$ZAP_SCRIPTS_DIR/zap-baseline.py" ]; then
  echo "[*] Running ZAP baseline script..."
  # Запускаем ZAP в фоновом режиме (daemon), затем запускаем скрипт.
  $ZAP_CMD -daemon -host 127.0.0.1 -port 8090 -config api.disablekey=true >/dev/null 2>&1 || true
  sleep 3
  python3 "$ZAP_SCRIPTS_DIR/zap-baseline.py" -t "$TARGET" -r "$BASELINE_HTML" -d || echo "[!] ZAP baseline exited non-zero"
  # Попытаемся корректно остановить ZAP
  pkill -f zaproxy || true
else
  echo "[!] zap-baseline.py not found in $ZAP_SCRIPTS_DIR — skipping ZAP baseline."
fi

# ---- 2) ZAP full scan (optionally long) ----
FULL_HTML="$REPORT_DIR/zap_full_$(timestamp).html"
if [ -x "$ZAP_SCRIPTS_DIR/zap-full-scan.py" ]; then
  echo "[*] Running ZAP full-scan script (this may take long)..."
  $ZAP_CMD -daemon -host 127.0.0.1 -port 8090 -config api.disablekey=true >/dev/null 2>&1 || true
  sleep 5
  python3 "$ZAP_SCRIPTS_DIR/zap-full-scan.py" -t "$TARGET" -r "$FULL_HTML" -d || echo "[!] ZAP full scan exited non-zero"
  pkill -f zaproxy || true
else
  echo "[!] zap-full-scan.py not found in $ZAP_SCRIPTS_DIR — skipping ZAP full scan."
fi

# ---- 3) Nikto ----
NIKTO_HTML="$REPORT_DIR/nikto_$(timestamp).html"
echo "[*] Running Nikto..."
nikto -h "$TARGET" -o "$NIKTO_HTML" -Format html || echo "[!] Nikto exited non-zero"

# ---- 4) Nmap ----
echo "[*] Running Nmap (top ports)..."
NMAP_PREFIX="$REPORT_DIR/nmap_$(timestamp)"
# Если TARGET — домен или IP, используем как есть. Если URL — извлечём хост:
NMAP_TARGET="$TARGET"
# попытка удалить схему
NMAP_TARGET="$(echo "$NMAP_TARGET" | sed -E 's#^https?://##' | sed -E 's#/.*$//')"
nmap -sS -sV -Pn --top-ports 1000 -oA "$NMAP_PREFIX" "$NMAP_TARGET" || echo "[!] Nmap exited non-zero"

# ---- 5) sqlmap (опционально) ----
if [ "$SQLMAP" = "true" ]; then
  echo "[*] Running sqlmap..."
  SQLMAP_OUTDIR="$REPORT_DIR/sqlmap_$(timestamp)"
  mkdir -p "$SQLMAP_OUTDIR"
  if [ -n "$SQLMAP_DATA" ]; then
    sqlmap -u "$TARGET" --data "$SQLMAP_DATA" --batch --output-dir="$SQLMAP_OUTDIR" $SQLMAP_OPTS || echo "[!] sqlmap exited non-zero"
  else
    sqlmap -u "$TARGET" --batch --output-dir="$SQLMAP_OUTDIR" $SQLMAP_OPTS || echo "[!] sqlmap exited non-zero"
  fi
  echo "[*] sqlmap output in: $SQLMAP_OUTDIR"
else
  echo "[*] sqlmap not enabled (set SQLMAP=true to enable)."
fi

echo "[*] All scans finished. Reports: $REPORT_DIR"
