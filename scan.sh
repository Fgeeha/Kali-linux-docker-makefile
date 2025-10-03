#!/usr/bin/env bash
set -euo pipefail

# Параметры (можно задавать через env)
TARGET="${TARGET:-}"
REPORT_DIR="${REPORT_DIR:-/zap/reports}"
ZAP_BASELINE="${ZAP_BASELINE:-/zap/zap-baseline.py}"
ZAP_FULL="${ZAP_FULL:-/zap/zap-full-scan.py}"
SQLMAP_OPTS="${SQLMAP_OPTS:-}"   # дополнительные опции для sqlmap
SQLMAP_DATA="${SQLMAP_DATA:-}"   # data for POST (если нужен)

if [ -z "$TARGET" ]; then
  echo "ERROR: TARGET is empty. Set TARGET=http://example.com"
  exit 2
fi

mkdir -p "$REPORT_DIR"

timestamp() {
  date +%Y%m%d_%H%M%S
}

echo "[*] Target: $TARGET"
echo "[*] Reports folder: $REPORT_DIR"

# 1) OWASP ZAP baseline (быстрый)
BASELINE_HTML="$REPORT_DIR/zap_baseline_$(timestamp).html"
echo "[*] Running ZAP baseline..."
python3 "$ZAP_BASELINE" -t "$TARGET" -r "$BASELINE_HTML" -d || echo "[!] ZAP baseline exited with non-zero code"

# 2) OWASP ZAP full (долго, опционально)
FULL_HTML="$REPORT_DIR/zap_full_$(timestamp).html"
echo "[*] Running ZAP full scan (this can take long)..."
python3 "$ZAP_FULL" -t "$TARGET" -r "$FULL_HTML" -d || echo "[!] ZAP full scan exited with non-zero code"

# 3) Nikto
NIKTO_HTML="$REPORT_DIR/nikto_$(timestamp).html"
echo "[*] Running Nikto ..."
nikto -h "$TARGET" -o "$NIKTO_HTML" -Format html || echo "[!] Nikto exited with non-zero code"

# 4) Nmap: быстрое сканирование версий (top ports)
echo "[*] Running Nmap ..."
NMAP_PREFIX="$REPORT_DIR/nmap_$(timestamp)"
nmap -sS -sV -Pn --top-ports 1000 -oA "$NMAP_PREFIX" "$TARGET" || echo "[!] Nmap exited with non-zero code"

# 5) sqlmap (опционально, только если указано SQLMAP=true)
# Для sqlmap нужно правило: явно включай его через переменную SQLMAP=true в make или env.
if [ "${SQLMAP:-false}" = "true" ]; then
  echo "[*] Running sqlmap (interactive/autonomous) ..."
  SQLMAP_OUTDIR="$REPORT_DIR/sqlmap_$(timestamp)"
  mkdir -p "$SQLMAP_OUTDIR"
  # Если передали POST data в SQLMAP_DATA — используем -p --data
  if [ -n "$SQLMAP_DATA" ]; then
    sqlmap -u "$TARGET" --data "$SQLMAP_DATA" --batch --output-dir="$SQLMAP_OUTDIR" $SQLMAP_OPTS || echo "[!] sqlmap exited with non-zero code"
  else
    # Попробуем автоматический тест параметров в URL
    sqlmap -u "$TARGET" --batch --output-dir="$SQLMAP_OUTDIR" $SQLMAP_OPTS || echo "[!] sqlmap exited with non-zero code"
  fi
  echo "[*] sqlmap reports in: $SQLMAP_OUTDIR"
else
  echo "[*] SQLMAP not enabled (set SQLMAP=true to enable)."
fi

echo "[*] All scans finished. Reports: $REPORT_DIR"
