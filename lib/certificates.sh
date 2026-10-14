#!/usr/bin/env bash
# Sourced by install-ubuntu.sh -- not meant to run standalone.
#
# Main menu option: manage the company certificate authority used by the Nginx
# HTTPS proxy on an existing installation, without rerunning the installer.

# True once an installation has written its configuration.
odoo_installation_present() {
  [[ -f "$SCRIPT_DIR/.env" ]] && grep -q '^ODOO_IMAGE=' "$SCRIPT_DIR/.env"
}

# Replaces KEY=... in .env, or appends it, keeping the file private.
set_env_value() {
  local key="$1" value="$2" tmp
  tmp="$(mktemp "$SCRIPT_DIR/.env.XXXXXX")"
  awk -v key="$key" -v value="$value" '
    index($0, key "=") == 1 { print key "=" value; done = 1; next }
    { print }
    END { if (!done) print key "=" value }
  ' "$SCRIPT_DIR/.env" > "$tmp"
  chmod 600 "$tmp"
  mv -- "$tmp" "$SCRIPT_DIR/.env"
}

# "2027-01-31 (812 days left)" for a certificate file.
certificate_expiry_summary() {
  local file="$1" end end_epoch days
  end="$(openssl x509 -noout -enddate -in "$file" 2>/dev/null | cut -d= -f2)" || return 1
  [[ -n "$end" ]] || return 1
  end_epoch="$(date -d "$end" +%s 2>/dev/null)" || return 1
  days=$(( (end_epoch - $(date +%s)) / 86400 ))
  printf '%s (%s days left)' "$(date -d "$end" +%F)" "$days"
}

certificate_days_left() {
  local end
  end="$(openssl x509 -noout -enddate -in "$1" 2>/dev/null | cut -d= -f2)" || return 1
  echo $(( ($(date -d "$end" +%s) - $(date +%s)) / 86400 ))
}

# Loads the proxy settings written by the installer.
load_proxy_settings_from_env() {
  PROXY_ENABLED="$(get_env_value PROXY_ENABLED)"
  PROXY_CERT_MODE="$(get_env_value PROXY_CERT_MODE)"
  PROXY_SERVER_NAME="$(get_env_value PROXY_SERVER_NAME)"
  PROXY_HTTP_PORT="$(get_env_value PROXY_HTTP_PORT)"
  ENTERPRISE_HTTPS_PORT="$(get_env_value ENTERPRISE_HTTPS_PORT)"
  COMMUNITY_HTTPS_PORT="$(get_env_value COMMUNITY_HTTPS_PORT)"
  NGINX_IMAGE="$(get_env_value NGINX_IMAGE)"
  COMMUNITY_WORKERS="$(get_env_value COMMUNITY_WORKERS)"
  ENTERPRISE_WORKERS="$(get_env_value ENTERPRISE_WORKERS)"
  NGINX_IMAGE="${NGINX_IMAGE:-$NGINX_DEFAULT_IMAGE}"
  valid_port "$PROXY_HTTP_PORT" || PROXY_HTTP_PORT=80
  valid_port "$ENTERPRISE_HTTPS_PORT" || ENTERPRISE_HTTPS_PORT=443
  valid_port "$COMMUNITY_HTTPS_PORT" || COMMUNITY_HTTPS_PORT=8443
  [[ "$COMMUNITY_WORKERS" =~ ^[0-9]+$ ]] || COMMUNITY_WORKERS=0
  [[ "$ENTERPRISE_WORKERS" =~ ^[0-9]+$ ]] || ENTERPRISE_WORKERS=0
  # Older installations stored a plain self-signed certificate.
  [[ "$PROXY_CERT_MODE" == "self-signed" ]] && PROXY_CERT_MODE="self-signed-legacy"
}

# Sets DOCKER to a working command for the pinned native engine.
resolve_certificate_docker_command() {
  command -v docker >/dev/null 2>&1 || { echo "Docker is not installed."; return 1; }
  resolve_install_docker_endpoint || return 1
  DOCKER=(docker --host "$INSTALL_DOCKER_ENDPOINT")
  if ! "${DOCKER[@]}" info >/dev/null 2>&1; then
    DOCKER=(sudo docker --host "$INSTALL_DOCKER_ENDPOINT")
    if ! "${DOCKER[@]}" info >/dev/null 2>&1; then
      echo "The Docker engine is not running. Start it with: sudo systemctl start docker"
      return 1
    fi
  fi
}

show_certificate_status() {
  local days
  section "CERTIFICATES" "Company certificate authority and HTTPS status"
  printf '  %-26s %s\n' "Reverse proxy" "$([[ "$PROXY_ENABLED" == "true" ]] && echo "Nginx enabled" || echo "not enabled")"
  case "$PROXY_CERT_MODE" in
    local-ca) printf '  %-26s %s\n' "HTTPS certificate source" "company certificate authority" ;;
    custom) printf '  %-26s %s\n' "HTTPS certificate source" "your own certificate files" ;;
    none) printf '  %-26s %s\n' "HTTPS certificate source" "none (HTTP only)" ;;
    self-signed-legacy) printf '  %-26s %s\n' "HTTPS certificate source" "self-signed (browsers show Not secure)" ;;
  esac
  [[ -n "$PROXY_SERVER_NAME" ]] && printf '  %-26s %s\n' "Server name" "$PROXY_SERVER_NAME"
  if [[ -f "$PROXY_CA_DIR/ca.crt" ]]; then
    printf '  %-26s %s\n' "Company CA" "$(openssl x509 -noout -subject -nameopt multiline -in "$PROXY_CA_DIR/ca.crt" | awk -F' = ' '/commonName/ {print $2}')"
    printf '  %-26s %s\n' "Company CA expires" "$(certificate_expiry_summary "$PROXY_CA_DIR/ca.crt")"
    days="$(certificate_days_left "$PROXY_CA_DIR/ca.crt")"
    if [[ -n "$days" ]] && (( days < 365 )); then
      printf '%b\n' "  ${COLOR_YELLOW}The company CA expires within a year: plan a new CA and install it on every device before then.${COLOR_RESET}"
    fi
  else
    printf '  %-26s %s\n' "Company CA" "not created yet"
  fi
  if [[ -f "$PROXY_CERT_DIR/fullchain.pem" ]]; then
    printf '  %-26s %s\n' "Server certificate expires" "$(certificate_expiry_summary "$PROXY_CERT_DIR/fullchain.pem")"
  fi
  if [[ "$PROXY_CERT_MODE" == "local-ca" ]]; then
    printf '  %-26s %s\n' "Device setup page" "$(proxy_ca_page_url)"
  fi
}

# Regenerates the Nginx files for the running editions and recreates Nginx.
apply_proxy_changes() {
  START_COMMUNITY="false"
  START_ENTERPRISE="false"
  [[ -n "$("${DOCKER[@]}" compose ps -q community 2>/dev/null)" ]] && START_COMMUNITY="true"
  [[ -n "$("${DOCKER[@]}" compose ps -q enterprise 2>/dev/null)" ]] && START_ENTERPRISE="true"
  if [[ "$START_COMMUNITY" != "true" && "$START_ENTERPRISE" != "true" ]]; then
    echo "No Odoo edition is running. Start Odoo first (docker compose up -d), then try again."
    return 1
  fi
  mkdir -p "$PROXY_CERT_DIR" "$PROXY_CONFIG_DIR/public"
  rm -f -- "$PROXY_CONFIG_DIR/public/"*
  write_ca_download_page
  write_nginx_config
  chmod 700 "$PROXY_CERT_DIR"
  chmod 600 "$PROXY_CERT_DIR"/*.pem 2>/dev/null || true
  verify_nginx_config || return 1
  echo "Restarting Nginx with the new certificate..."
  "${DOCKER[@]}" compose --profile proxy up -d --wait --wait-timeout 120 --force-recreate nginx || return 1
  echo
  printf '%b\n' "${COLOR_GREEN}Done.${COLOR_RESET} Open $(proxy_ca_page_url) once on each computer or phone to install the company certificate."
}

backup_company_ca() {
  local archive
  if [[ ! -f "$PROXY_CA_DIR/ca.key" ]]; then
    echo "There is no company CA to back up yet."
    return 1
  fi
  mkdir -p "$SCRIPT_DIR/backups"
  archive="$SCRIPT_DIR/backups/odoo-company-ca-$(date +%Y%m%d-%H%M%S).tar.gz"
  (umask 077 && tar -czf "$archive" -C "$SCRIPT_DIR/$PROXY_CONFIG_DIR" ca)
  chmod 600 "$archive"
  echo "Company CA saved to $archive"
  echo "Keep a copy off this server. It contains the CA private key; anyone holding it can"
  echo "create certificates your devices trust, so store it like a password."
}

run_certificate_manager() {
  local choice
  cd "$SCRIPT_DIR" || return 1
  if ! odoo_installation_present; then
    echo "Odoo is not installed yet. Install Odoo first; the company CA is created for an existing installation."
    return 1
  fi
  load_proxy_settings_from_env
  show_certificate_status

  if [[ "$PROXY_ENABLED" != "true" ]]; then
    echo
    echo "HTTPS with the company CA needs the Nginx reverse proxy, which this installation does not use."
    echo "Run the installer again (Install), answer y to \"Put Nginx in front of Odoo?\" and choose option 1."
    return 1
  fi
  if [[ "$PROXY_CERT_MODE" == "none" ]]; then
    echo
    echo "This installation serves Odoo over HTTP only, so its ports are set up for HTTP."
    echo "Run the installer again (Install) and choose HTTPS with the company CA (option 1)."
    return 1
  fi

  echo
  echo "What would you like to do?"
  if [[ "$PROXY_CERT_MODE" == "local-ca" ]]; then
    echo "  1) Refresh the HTTPS certificate and device setup page from the company CA"
  else
    echo "  1) Switch HTTPS to the company CA (creates it; devices install it once)"
  fi
  echo "  2) Renew the server certificate now (devices keep working, nothing to reinstall)"
  echo "  3) Back up the company CA"
  echo "  4) Exit"
  read_choice choice "Choose an option [1]: " "" "1 2 3 4"
  case "$choice" in
    4) return 0 ;;
    3) backup_company_ca; return ;;
  esac
  if [[ "$choice" == "2" && "$PROXY_CERT_MODE" != "local-ca" ]]; then
    echo "The server certificate comes from your own files; replace them by rerunning the installer"
    echo "with option 2, or use option 1 here to switch to the company CA."
    return 1
  fi
  if [[ "$PROXY_CERT_MODE" == "custom" ]] &&
     ! ask_yes_no "Replace your own certificate files with the company CA? [y/N]: "; then
    echo "Nothing was changed."
    return 0
  fi

  resolve_certificate_docker_command || return 1
  PROXY_CERT_MODE="local-ca"
  [[ "$choice" == "2" ]] && rm -f -- "$PROXY_CERT_DIR/generated-names.txt"
  ensure_ca_signed_certificate || return 1
  set_env_value PROXY_CERT_MODE local-ca
  apply_proxy_changes
}
