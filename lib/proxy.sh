#!/usr/bin/env bash
# Sourced by install-ubuntu.sh -- not meant to run standalone.
#
# Optional Nginx reverse proxy in front of Odoo. It terminates HTTPS (the
# Odoo 20 web client needs a secure context, e.g. for the clipboard API),
# routes /websocket to Odoo's evented port when workers are enabled, and lets
# the Odoo ports stay on 127.0.0.1.

NGINX_DEFAULT_IMAGE="nginx:1.30.0-alpine"
PROXY_CONFIG_DIR="config/nginx"
PROXY_CERT_DIR="$PROXY_CONFIG_DIR/certs"
# Container-side ports; compose.yaml maps the chosen host ports onto these.
PROXY_CONTAINER_ENTERPRISE_PORT=8443
PROXY_CONTAINER_COMMUNITY_PORT=9443

valid_server_name() {
  valid_ipv4 "$1" ||
    [[ "$1" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$ ]]
}

# Address shown in URLs: "https://name" for 443, "https://name:port" otherwise.
proxy_url() {
  local port="$1"
  if [[ "$port" == "443" ]]; then
    printf 'https://%s' "$PROXY_SERVER_NAME"
  else
    printf 'https://%s:%s' "$PROXY_SERVER_NAME" "$port"
  fi
}

# Subject alternative names for the self-signed certificate: the chosen name
# plus every local IPv4 address, so the same certificate works on the LAN.
self_signed_subject_alt_names() {
  local -a entries=() ip
  if valid_ipv4 "$PROXY_SERVER_NAME"; then
    entries+=("IP:$PROXY_SERVER_NAME")
  else
    entries+=("DNS:$PROXY_SERVER_NAME")
  fi
  entries+=("DNS:localhost" "IP:127.0.0.1")
  # Host addresses only; Docker bridge interfaces are not reachable by users.
  for ip in $(ip -4 -o addr show scope global 2>/dev/null |
              awk '$2 !~ /^(docker|br-|veth|cni|flannel|virbr)/ {sub(/\/.*/, "", $4); print $4}'); do
    valid_ipv4 "$ip" && entries+=("IP:$ip")
  done
  printf '%s\n' "${entries[@]}" | awk '!seen[$0]++' | paste -sd, -
}

# Creates (or keeps, when the names did not change) a self-signed certificate.
ensure_self_signed_certificate() {
  local san names_file="$PROXY_CERT_DIR/self-signed-names.txt"
  san="$(self_signed_subject_alt_names)"
  mkdir -p "$PROXY_CERT_DIR"
  if [[ -f "$PROXY_CERT_DIR/fullchain.pem" && -f "$PROXY_CERT_DIR/privkey.pem" &&
        -f "$names_file" && "$(cat "$names_file")" == "$san" ]] &&
     openssl x509 -checkend 2592000 -noout -in "$PROXY_CERT_DIR/fullchain.pem" >/dev/null 2>&1; then
    echo "Reusing the existing self-signed certificate for $PROXY_SERVER_NAME."
    return 0
  fi
  echo "Creating a self-signed certificate for $PROXY_SERVER_NAME..."
  if ! (umask 077 && openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 825 \
        -subj "/CN=$PROXY_SERVER_NAME" -addext "subjectAltName=$san" \
        -keyout "$PROXY_CERT_DIR/privkey.pem" -out "$PROXY_CERT_DIR/fullchain.pem" >/dev/null 2>&1); then
    echo "OpenSSL could not create the self-signed certificate."
    return 1
  fi
  printf '%s' "$san" > "$names_file"
}

# Copies a user-provided certificate and key after checking that they match.
install_custom_certificate() {
  local cert="$1" key="$2" cert_pub key_pub
  if ! openssl x509 -noout -in "$cert" >/dev/null 2>&1; then
    echo "$cert is not a readable PEM certificate."
    return 1
  fi
  cert_pub="$(openssl x509 -noout -pubkey -in "$cert" 2>/dev/null)"
  key_pub="$(openssl pkey -pubout -in "$key" 2>/dev/null)"
  if [[ -z "$key_pub" || "$cert_pub" != "$key_pub" ]]; then
    echo "The private key does not match the certificate."
    return 1
  fi
  mkdir -p "$PROXY_CERT_DIR"
  (umask 077 && cp -- "$cert" "$PROXY_CERT_DIR/fullchain.pem" && cp -- "$key" "$PROXY_CERT_DIR/privkey.pem")
  rm -f -- "$PROXY_CERT_DIR/self-signed-names.txt"
}

# One HTTPS server block proxying to an Odoo service. With workers, Odoo serves
# websockets on its evented port 8072; in threaded mode on 8069 itself.
nginx_odoo_server_block() {
  local listen_port="$1" service="$2" workers="$3" chat_port=8069
  (( workers > 0 )) && chat_port=8072
  cat <<EOF
server {
    listen $listen_port ssl;
    http2 on;
    server_name _;

    ssl_certificate /etc/nginx/certs/fullchain.pem;
    ssl_certificate_key /etc/nginx/certs/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;

    location /websocket {
        set \$odoo_chat http://$service:$chat_port;
        proxy_pass \$odoo_chat;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        include /etc/nginx/conf.d/odoo-proxy-headers.inc;
        proxy_read_timeout 3600s;
    }

    location / {
        set \$odoo_web http://$service:8069;
        proxy_pass \$odoo_web;
        include /etc/nginx/conf.d/odoo-proxy-headers.inc;
        proxy_redirect off;
    }
}

EOF
}

# Writes config/nginx/conf.d for the selected editions.
write_nginx_config() {
  local conf_dir="$PROXY_CONFIG_DIR/conf.d" redirect_port
  mkdir -p "$conf_dir"
  if [[ "$START_ENTERPRISE" == "true" ]]; then
    redirect_port="$ENTERPRISE_HTTPS_PORT"
  else
    redirect_port="$COMMUNITY_HTTPS_PORT"
  fi

  cat > "$conf_dir/odoo-proxy-headers.inc" <<'EOF'
# Generated by the Odoo installer; rerun the installer to change it.
proxy_set_header Host $http_host;
proxy_set_header X-Forwarded-Host $http_host;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
proxy_set_header X-Real-IP $remote_addr;
EOF

  {
    cat <<EOF
# Generated by the Odoo installer; rerun the installer to change it.
# Odoo services are resolved per request so Nginx starts even when an edition
# is stopped or not selected.
resolver 127.0.0.11 valid=10s ipv6=off;

map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ''      close;
}

client_max_body_size 512m;
proxy_connect_timeout 720s;
proxy_send_timeout 720s;
proxy_read_timeout 720s;
proxy_buffers 16 64k;
proxy_buffer_size 128k;

gzip on;
gzip_types text/css text/plain text/xml application/xml application/json application/javascript image/svg+xml;
gzip_min_length 1024;

server_tokens off;

# Plain HTTP only redirects to HTTPS (and answers the container health check).
server {
    listen 80 default_server;
    server_name _;

    location = /nginx-health {
        access_log off;
        return 200 "ok\n";
    }

    location / {
        return 301 $(proxy_url "$redirect_port")\$request_uri;
    }
}

EOF
    if [[ "$START_ENTERPRISE" == "true" ]]; then
      echo "# Odoo Enterprise: $(proxy_url "$ENTERPRISE_HTTPS_PORT")"
      nginx_odoo_server_block "$PROXY_CONTAINER_ENTERPRISE_PORT" enterprise "$ENTERPRISE_WORKERS"
    fi
    if [[ "$START_COMMUNITY" == "true" ]]; then
      echo "# Odoo Community: $(proxy_url "$COMMUNITY_HTTPS_PORT")"
      nginx_odoo_server_block "$PROXY_CONTAINER_COMMUNITY_PORT" community "$COMMUNITY_WORKERS"
    fi
  } > "$conf_dir/odoo.conf"
}

# Checks the generated configuration and certificate with the pinned image.
verify_nginx_config() {
  local output
  if ! output="$("${DOCKER[@]}" run --rm \
      -v "$SCRIPT_DIR/$PROXY_CONFIG_DIR/conf.d:/etc/nginx/conf.d:ro" \
      -v "$SCRIPT_DIR/$PROXY_CERT_DIR:/etc/nginx/certs:ro" \
      "$NGINX_IMAGE" nginx -t 2>&1)"; then
    echo "The generated Nginx configuration was rejected:"
    printf '%s\n' "$output"
    return 1
  fi
}
