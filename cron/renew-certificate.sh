#!/usr/bin/env bash
# Weekly check run by the odoo-installer-cert-renewal systemd timer: renews the
# Nginx HTTPS certificate from the company CA when it has fewer than 30 days
# left or the server's names/addresses changed, then reloads Nginx. Devices
# keep trusting the new certificate because the CA does not change.

set -uo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$PROJECT_DIR"
LOG_FILE="$PROJECT_DIR/logs/certificate-renewal.log"
cd "$PROJECT_DIR" || exit 1
mkdir -p "$PROJECT_DIR/logs"

log() {
  printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$LOG_FILE"
}

# Files written while running as root are handed back to the installation
# owner, so a later installer run as that user can still update them.
restore_ownership() {
  local owner
  owner="$(stat -c '%u:%g' "$PROJECT_DIR")"
  chown -R "$owner" "$PROJECT_DIR/config/nginx/certs" "$PROJECT_DIR/config/nginx/ca" \
    "$PROJECT_DIR/logs" 2>/dev/null || true
}

trim_log() {
  local tmp
  [[ "$(wc -l < "$LOG_FILE")" -gt 1000 ]] || return 0
  tmp="$(mktemp)"
  tail -n 500 "$LOG_FILE" > "$tmp" && cat "$tmp" > "$LOG_FILE"
  rm -f -- "$tmp"
}

COLOR_YELLOW="" COLOR_GREEN="" COLOR_RESET="" COLOR_BOLD="" COLOR_CYAN=""
# shellcheck source=/dev/null
for lib in ui config proxy certificates; do source "$PROJECT_DIR/lib/$lib.sh"; done

finish() {
  restore_ownership
  trim_log
  exit "$1"
}

if ! odoo_installation_present; then
  log "SKIP no Odoo installation found"
  finish 0
fi
load_proxy_settings_from_env
if [[ "$PROXY_ENABLED" != "true" || "$PROXY_CERT_MODE" != "local-ca" ]]; then
  log "SKIP HTTPS does not use the company CA (mode: ${PROXY_CERT_MODE:-none})"
  finish 0
fi
if [[ ! -f "$PROXY_CA_DIR/ca.key" || ! -f "$PROXY_CA_DIR/ca.crt" ]]; then
  log "ERROR the company CA is missing from $PROXY_CA_DIR; restore it from backup"
  finish 1
fi
# Never replace the CA automatically: every device would have to reinstall it.
if ! openssl x509 -checkend 0 -noout -in "$PROXY_CA_DIR/ca.crt" >/dev/null 2>&1; then
  log "ERROR the company CA has expired; create a new one from the installer (main menu option 7) and install it on every device"
  finish 1
fi

before="$(openssl x509 -noout -fingerprint -sha256 -in "$PROXY_CERT_DIR/fullchain.pem" 2>/dev/null)"
if ! output="$(ensure_ca_signed_certificate 2>&1)"; then
  log "ERROR could not issue the certificate: ${output//$'\n'/ }"
  finish 1
fi
chmod 600 "$PROXY_CERT_DIR"/*.pem 2>/dev/null
after="$(openssl x509 -noout -fingerprint -sha256 -in "$PROXY_CERT_DIR/fullchain.pem" 2>/dev/null)"
expiry="$(certificate_expiry_summary "$PROXY_CERT_DIR/fullchain.pem")"

status=0
if [[ "$before" != "$after" ]]; then
  if docker compose --profile proxy exec -T nginx nginx -s reload >/dev/null 2>&1; then
    log "RENEWED server certificate for $PROXY_SERVER_NAME; valid until $expiry; Nginx reloaded"
  else
    log "ERROR renewed the certificate (valid until $expiry) but could not reload Nginx; run: docker compose --profile proxy restart nginx"
    status=1
  fi
else
  log "OK server certificate valid until $expiry"
fi

ca_days="$(certificate_days_left "$PROXY_CA_DIR/ca.crt")"
if [[ -n "$ca_days" ]] && (( ca_days < 365 )); then
  log "WARNING the company CA expires on $(certificate_expiry_summary "$PROXY_CA_DIR/ca.crt"); prepare a new CA and install it on every device before then"
fi
finish "$status"
