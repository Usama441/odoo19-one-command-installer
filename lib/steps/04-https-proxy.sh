#!/usr/bin/env bash
# Sourced by install-ubuntu.sh -- not meant to run standalone.

# Reads a port, rejecting values used by the Odoo/pgAdmin ports or listed in
# the remaining arguments (ports already chosen for the proxy).
read_proxy_port() {
  local target="$1" prompt="$2" default_port="$3" value taken
  shift 3
  while true; do
    read -r -p "$prompt [$default_port]: " value
    value="${value:-$default_port}"
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

step_configure_proxy() {
  local default_enabled default_name choice cert_path key_path

  PROXY_ENABLED="false"
  PROXY_CERT_MODE="self-signed"
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
  [[ "$PROXY_CERT_MODE" == "custom" ]] || PROXY_CERT_MODE="self-signed"

  section "4/6" "Choose optional HTTPS (Nginx reverse proxy)"
  echo "Nginx serves Odoo over HTTPS and keeps the Odoo ports private on this server."
  echo "It is needed for the Odoo 20 web client on a network address (secure browser"
  echo "context) and for live updates (websocket) when production workers are enabled."

  if [[ "$PROXY_ENABLED" == "true" ]]; then
    default_enabled="y"
  elif [[ -z "$PROXY_ENABLED" && "$DEPLOYMENT_MODE" == "production" && "$BIND_ADDRESS" != "127.0.0.1" ]]; then
    default_enabled="y"
  else
    default_enabled="n"
  fi
  if ask_yes_no "Put Nginx with HTTPS in front of Odoo? [$([[ "$default_enabled" == "y" ]] && echo "Y/n" || echo "y/N")]: " "$default_enabled"; then
    PROXY_ENABLED="true"
  else
    PROXY_ENABLED="false"
    echo "HTTPS proxy not selected; Odoo is served directly over HTTP."
    return
  fi

  if [[ "$BIND_ADDRESS" == "127.0.0.1" ]]; then
    printf '%b\n' "${COLOR_YELLOW}The bind address is localhost only, so HTTPS will only be reachable from this machine.${COLOR_RESET}"
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
    read -r -p "Server name or IP [$default_name]: " PROXY_SERVER_NAME
    PROXY_SERVER_NAME="${PROXY_SERVER_NAME:-$default_name}"
    PROXY_SERVER_NAME="${PROXY_SERVER_NAME//[[:space:]]/}"
    if valid_server_name "$PROXY_SERVER_NAME"; then break; fi
    echo "Please enter an IPv4 address such as 192.168.1.10 or a name such as erp.example.com."
  done

  echo
  read_proxy_port PROXY_HTTP_PORT "HTTP port (redirects to HTTPS)" "$PROXY_HTTP_PORT"
  if [[ "$START_ENTERPRISE" == "true" ]]; then
    read_proxy_port ENTERPRISE_HTTPS_PORT "Enterprise HTTPS port" "$ENTERPRISE_HTTPS_PORT" "$PROXY_HTTP_PORT"
  fi
  if [[ "$START_COMMUNITY" == "true" ]]; then
    if [[ "$START_ENTERPRISE" != "true" && "$COMMUNITY_HTTPS_PORT" == "8443" ]]; then
      COMMUNITY_HTTPS_PORT="443"
    fi
    read_proxy_port COMMUNITY_HTTPS_PORT "Community HTTPS port" "$COMMUNITY_HTTPS_PORT" "$PROXY_HTTP_PORT" \
      "$([[ "$START_ENTERPRISE" == "true" ]] && echo "$ENTERPRISE_HTTPS_PORT")"
  fi
  # compose.yaml publishes both HTTPS ports; keep the unused one distinct.
  if [[ "$ENTERPRISE_HTTPS_PORT" == "$COMMUNITY_HTTPS_PORT" ]]; then
    if [[ "$START_ENTERPRISE" == "true" ]]; then COMMUNITY_HTTPS_PORT="8443"; else ENTERPRISE_HTTPS_PORT="8444"; fi
  fi

  echo
  echo "Which HTTPS certificate should Nginx use?"
  echo "  1) Self-signed certificate (LAN/testing; browsers ask to proceed once)"
  echo "  2) My own certificate files (full chain + private key, e.g. from your CA)"
  read_choice choice "Choose a certificate option [$([[ "$PROXY_CERT_MODE" == "custom" ]] && echo 2 || echo 1)]: " \
    "$([[ "$PROXY_CERT_MODE" == "custom" ]] && echo 2 || echo 1)" "1 2"
  if [[ "$choice" == "1" ]]; then
    PROXY_CERT_MODE="self-signed"
    PROXY_CUSTOM_CERT=""
    PROXY_CUSTOM_KEY=""
    return
  fi

  PROXY_CERT_MODE="custom"
  if [[ -f "$PROXY_CERT_DIR/fullchain.pem" && -f "$PROXY_CERT_DIR/privkey.pem" &&
        ! -f "$PROXY_CERT_DIR/self-signed-names.txt" ]] &&
     ask_yes_no "Keep the certificate already installed for Nginx? [Y/n]: " "y"; then
    PROXY_CUSTOM_CERT=""
    PROXY_CUSTOM_KEY=""
    return
  fi
  while true; do
    read -r -p "Path to the certificate (full chain, PEM): " cert_path
    read -r -p "Path to the private key (PEM): " key_path
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
