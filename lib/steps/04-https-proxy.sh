#!/usr/bin/env bash
# Sourced by install-ubuntu.sh -- not meant to run standalone.

# Reads a port, rejecting values used by the Odoo/pgAdmin ports or listed in
# the remaining arguments (ports already chosen for the proxy).
read_proxy_port() {
  local target="$1" prompt="$2" default_port="$3" value taken
  shift 3
  while true; do
    read_value value "$prompt [$default_port]: "
    if ! valid_port "$value"; then
      echo "Please enter a port number from 1 to 65535."
      continue
    fi
    value="$((10#$value))"
    for taken in "$COMMUNITY_PORT" "$ENTERPRISE_PORT" "$@"; do
      if [[ "$value" == "$taken" ]]; then
        echo "Port $value is already used by another service of this installation."
        continue 2
      fi
    done
    if [[ "$PGADMIN_ENABLED" == "true" && "$value" == "$PGADMIN_PORT" ]]; then
      echo "Port $value is already used by pgAdmin."
      continue
    fi
    printf -v "$target" '%s' "$value"
    return
  done
}

# Asked in step 2, right after the bind address and before the Odoo ports:
# with Nginx the Odoo ports become internal, so they are not asked at all.
ask_proxy_enabled() {
  local default_enabled

  PROXY_ENABLED="false"
  PROXY_CERT_MODE="local-ca"
  PROXY_SERVER_NAME=""
  PROXY_HTTP_PORT="80"
  ENTERPRISE_HTTPS_PORT="443"
  COMMUNITY_HTTPS_PORT="8443"
  NGINX_IMAGE="$NGINX_DEFAULT_IMAGE"
  if [[ -f .env ]]; then
    PROXY_ENABLED="$(get_env_value PROXY_ENABLED)"
    PROXY_CERT_MODE="$(get_env_value PROXY_CERT_MODE)"
    PROXY_SERVER_NAME="$(get_env_value PROXY_SERVER_NAME)"
    valid_port "$(get_env_value PROXY_HTTP_PORT)" && PROXY_HTTP_PORT="$(get_env_value PROXY_HTTP_PORT)"
    valid_port "$(get_env_value ENTERPRISE_HTTPS_PORT)" && ENTERPRISE_HTTPS_PORT="$(get_env_value ENTERPRISE_HTTPS_PORT)"
    valid_port "$(get_env_value COMMUNITY_HTTPS_PORT)" && COMMUNITY_HTTPS_PORT="$(get_env_value COMMUNITY_HTTPS_PORT)"
    [[ -n "$(get_env_value NGINX_IMAGE)" ]] && NGINX_IMAGE="$(get_env_value NGINX_IMAGE)"
  fi
  # Earlier versions created a plain self-signed certificate; they now use the CA.
  case "$PROXY_CERT_MODE" in
    custom|none) ;;
    *) PROXY_CERT_MODE="local-ca" ;;
  esac

  echo
  printf '%b\n' "${COLOR_BOLD}Nginx reverse proxy${COLOR_RESET}"
  echo "Nginx sits in front of Odoo and keeps the Odoo ports private on this server."
  echo "It routes live updates (websocket) to Odoo when production workers are enabled,"
  echo "and with HTTPS gives the Odoo 20 web client the secure browser context it needs"
  echo "on a network address. Plain HTTP through Nginx is also possible."

  if [[ "$PROXY_ENABLED" == "true" ]]; then
    default_enabled="y"
  elif [[ -z "$PROXY_ENABLED" && "$DEPLOYMENT_MODE" == "production" && "$BIND_ADDRESS" != "127.0.0.1" ]]; then
    default_enabled="y"
  else
    default_enabled="n"
  fi
  if ask_yes_no "Put Nginx in front of Odoo? [$([[ "$default_enabled" == "y" ]] && echo "Y/n" || echo "y/N")]: "; then
    PROXY_ENABLED="true"
  else
    PROXY_ENABLED="false"
    echo "Nginx not selected; Odoo is served directly over HTTP on its own ports."
    return
  fi
  echo "Nginx selected: the address, certificate and Nginx ports are asked in step 4."
}

# Internal Odoo port used behind Nginx: the saved one, else the default.
proxy_internal_odoo_port() {
  local key="$1" default_port="$2" saved=""
  [[ -f .env ]] && saved="$(get_env_value "$key")"
  if valid_port "$saved"; then
    echo "$((10#$saved))"
  else
    echo "$default_port"
  fi
}

step_configure_proxy() {
  local default_name choice default_choice cert_path key_path

  if [[ "$PROXY_ENABLED" != "true" ]]; then
    return
  fi
  section "4/6" "Configure the Nginx reverse proxy"

  if [[ "$BIND_ADDRESS" == "127.0.0.1" ]]; then
    printf '%b\n' "${COLOR_YELLOW}The bind address is localhost only, so Nginx will only be reachable from this machine.${COLOR_RESET}"
  fi

  default_name="$PROXY_SERVER_NAME"
  if [[ -z "$default_name" ]]; then
    case "$BIND_ADDRESS" in
      0.0.0.0) default_name="$(hostname -I 2>/dev/null | awk '{print $1}')" ;;
      *) default_name="$BIND_ADDRESS" ;;
    esac
    default_name="${default_name:-localhost}"
  fi
  echo
  echo "Enter the address users will type in the browser: this server's IP or a domain name."
  while true; do
    read_value PROXY_SERVER_NAME "Server name or IP [$default_name]: "
    PROXY_SERVER_NAME="${PROXY_SERVER_NAME//[[:space:]]/}"
    if valid_server_name "$PROXY_SERVER_NAME"; then break; fi
    echo "Please enter an IPv4 address such as 192.168.1.10 or a name such as erp.example.com."
  done

  echo
  echo "How should Nginx serve Odoo?"
  echo "  1) HTTPS with a local company certificate authority (LAN; install it once per device)"
  echo "  2) HTTPS with my own certificate files (full chain + private key, e.g. from your CA)"
  echo "  3) HTTP only, no certificate (Odoo 20 needs HTTPS or localhost for some browser features)"
  case "$PROXY_CERT_MODE" in
    custom) default_choice=2 ;;
    none) default_choice=3 ;;
    *) default_choice=1 ;;
  esac
  read_choice choice "Choose an option [$default_choice]: " "" "1 2 3"
  case "$choice" in
    1) PROXY_CERT_MODE="local-ca" ;;
    2) PROXY_CERT_MODE="custom" ;;
    3) PROXY_CERT_MODE="none" ;;
  esac

  echo
  if [[ "$PROXY_CERT_MODE" == "none" ]]; then
    configure_proxy_http_ports
  else
    configure_proxy_https_ports
  fi

  PROXY_CUSTOM_CERT=""
  PROXY_CUSTOM_KEY=""
  if [[ "$PROXY_CERT_MODE" != "custom" ]]; then
    return
  fi
  if [[ -f "$PROXY_CERT_DIR/fullchain.pem" && -f "$PROXY_CERT_DIR/privkey.pem" &&
        ! -f "$PROXY_CERT_DIR/generated-names.txt" && ! -f "$PROXY_CERT_DIR/self-signed-names.txt" ]] &&
     ask_yes_no "Keep the certificate already installed for Nginx? [Y/n]: "; then
    return
  fi
  while true; do
    read_value cert_path "Path to the certificate (full chain, PEM): "
    read_value key_path "Path to the private key (PEM): "
    cert_path="${cert_path/#\~/$HOME}"
    key_path="${key_path/#\~/$HOME}"
    if [[ ! -r "$cert_path" || ! -r "$key_path" ]]; then
      echo "Both files must exist and be readable."
      continue
    fi
    PROXY_CUSTOM_CERT="$cert_path"
    PROXY_CUSTOM_KEY="$key_path"
    if openssl x509 -noout -in "$cert_path" >/dev/null 2>&1 &&
       [[ "$(openssl x509 -noout -pubkey -in "$cert_path" 2>/dev/null)" == "$(openssl pkey -pubout -in "$key_path" 2>/dev/null)" ]]; then
      break
    fi
    echo "The certificate is not valid PEM or the private key does not match it."
  done
}

# HTTPS: port 80 redirects to HTTPS; each selected edition gets an HTTPS port.
configure_proxy_https_ports() {
  [[ "$PROXY_HTTP_PORT" == "$ENTERPRISE_HTTPS_PORT" || "$PROXY_HTTP_PORT" == "$COMMUNITY_HTTPS_PORT" ]] && PROXY_HTTP_PORT="80"
  read_proxy_port PROXY_HTTP_PORT "HTTP port (redirects to HTTPS)" "$PROXY_HTTP_PORT"
  if [[ "$START_ENTERPRISE" == "true" ]]; then
    [[ "$ENTERPRISE_HTTPS_PORT" == "$PROXY_HTTP_PORT" ]] && ENTERPRISE_HTTPS_PORT="443"
    read_proxy_port ENTERPRISE_HTTPS_PORT "Enterprise HTTPS port" "$ENTERPRISE_HTTPS_PORT" "$PROXY_HTTP_PORT"
  fi
  if [[ "$START_COMMUNITY" == "true" ]]; then
    if [[ "$START_ENTERPRISE" != "true" && "$COMMUNITY_HTTPS_PORT" == "8443" ]]; then
      COMMUNITY_HTTPS_PORT="443"
    fi
    [[ "$COMMUNITY_HTTPS_PORT" == "$PROXY_HTTP_PORT" ]] && COMMUNITY_HTTPS_PORT="8443"
    read_proxy_port COMMUNITY_HTTPS_PORT "Community HTTPS port" "$COMMUNITY_HTTPS_PORT" "$PROXY_HTTP_PORT" \
      "$([[ "$START_ENTERPRISE" == "true" ]] && echo "$ENTERPRISE_HTTPS_PORT")"
  fi
  # compose.yaml publishes both HTTPS ports; keep the unused one distinct.
  if [[ "$ENTERPRISE_HTTPS_PORT" == "$COMMUNITY_HTTPS_PORT" ]]; then
    if [[ "$START_ENTERPRISE" == "true" ]]; then COMMUNITY_HTTPS_PORT="8443"; else ENTERPRISE_HTTPS_PORT="8444"; fi
  fi
}

# HTTP only: the first selected edition is served on the HTTP port; with both
# editions, Community gets its own HTTP port. The HTTPS listener stays unused
# and is published on 127.0.0.1 only.
configure_proxy_http_ports() {
  local main_label="Odoo"
  [[ "$START_ENTERPRISE" == "true" ]] && main_label="Enterprise" || main_label="Community"
  [[ "$PROXY_HTTP_PORT" == "443" ]] && PROXY_HTTP_PORT="80"
  read_proxy_port PROXY_HTTP_PORT "$main_label HTTP port" "$PROXY_HTTP_PORT"
  if [[ "$START_ENTERPRISE" == "true" && "$START_COMMUNITY" == "true" ]]; then
    [[ "$COMMUNITY_HTTPS_PORT" == "8443" || "$COMMUNITY_HTTPS_PORT" == "$PROXY_HTTP_PORT" ]] && COMMUNITY_HTTPS_PORT="8080"
    read_proxy_port COMMUNITY_HTTPS_PORT "Community HTTP port" "$COMMUNITY_HTTPS_PORT" "$PROXY_HTTP_PORT"
  fi
  [[ "$COMMUNITY_HTTPS_PORT" == "$PROXY_HTTP_PORT" ]] && COMMUNITY_HTTPS_PORT="8080"
  [[ "$ENTERPRISE_HTTPS_PORT" == "$PROXY_HTTP_PORT" || "$ENTERPRISE_HTTPS_PORT" == "$COMMUNITY_HTTPS_PORT" ]] && ENTERPRISE_HTTPS_PORT="8444"
  return 0
}
