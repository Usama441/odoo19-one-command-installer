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
PROXY_CA_DIR="$PROXY_CONFIG_DIR/ca"
# Container-side ports; compose.yaml maps the chosen host ports onto these.
PROXY_CONTAINER_ENTERPRISE_PORT=8443
PROXY_CONTAINER_COMMUNITY_PORT=9443

valid_server_name() {
  valid_ipv4 "$1" ||
    [[ "$1" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$ ]]
}

# Address shown in URLs, without the port when it is the scheme's default.
proxy_url() {
  local port="$1" scheme="https" default_port=443
  if [[ "$PROXY_CERT_MODE" == "none" ]]; then
    scheme="http"
    default_port=80
  fi
  if [[ "$port" == "$default_port" ]]; then
    printf '%s://%s' "$scheme" "$PROXY_SERVER_NAME"
  else
    printf '%s://%s:%s' "$scheme" "$PROXY_SERVER_NAME" "$port"
  fi
}

# Public URL of each edition behind the proxy. In HTTP-only mode the first
# selected edition uses the HTTP port and Community (with both) its own port.
proxy_enterprise_url() {
  if [[ "$PROXY_CERT_MODE" == "none" ]]; then
    proxy_url "$PROXY_HTTP_PORT"
  else
    proxy_url "$ENTERPRISE_HTTPS_PORT"
  fi
}

proxy_community_url() {
  if [[ "$PROXY_CERT_MODE" == "none" && "$START_ENTERPRISE" != "true" ]]; then
    proxy_url "$PROXY_HTTP_PORT"
  else
    proxy_url "$COMMUNITY_HTTPS_PORT"
  fi
}

proxy_mode_label() {
  case "$PROXY_CERT_MODE" in
    none) printf 'Nginx, HTTP only (no certificate)' ;;
    custom) printf 'Nginx, HTTPS with your certificate for %s' "$PROXY_SERVER_NAME" ;;
    *) printf 'Nginx, HTTPS with the local company certificate authority for %s' "$PROXY_SERVER_NAME" ;;
  esac
}

# Page on the HTTP port where devices download the local CA certificate.
proxy_ca_page_url() {
  if [[ "$PROXY_HTTP_PORT" == "80" ]]; then
    printf 'http://%s/' "$PROXY_SERVER_NAME"
  else
    printf 'http://%s:%s/' "$PROXY_SERVER_NAME" "$PROXY_HTTP_PORT"
  fi
}

# Subject alternative names for the server certificate: the chosen name plus
# every local IPv4 address, so the same certificate works on the LAN.
server_subject_alt_names() {
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

# The local certificate authority is created once and then always reused:
# devices trust it once, so replacing it would force every device to
# reinstall it. Its private key never leaves config/nginx/ca.
ensure_local_ca() {
  local ca_dir="$PROXY_CA_DIR" ca_name
  mkdir -p "$ca_dir"
  chmod 700 "$ca_dir"
  if [[ -f "$ca_dir/ca.key" && -f "$ca_dir/ca.crt" ]] &&
     openssl x509 -checkend 0 -noout -in "$ca_dir/ca.crt" >/dev/null 2>&1; then
    echo "Reusing the local certificate authority ($(openssl x509 -noout -subject -nameopt multiline -in "$ca_dir/ca.crt" | awk -F' = ' '/commonName/ {print $2}'))."
    return 0
  fi
  ca_name="Odoo Local CA ($(hostname -s 2>/dev/null || echo server))"
  echo "Creating the local certificate authority \"$ca_name\" (valid for 10 years)..."
  if ! (umask 077 && openssl req -x509 -newkey rsa:3072 -nodes -sha256 -days 3650 \
        -subj "/CN=$ca_name/O=Odoo installer" \
        -addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
        -addext "keyUsage=critical,keyCertSign,cRLSign" \
        -addext "subjectKeyIdentifier=hash" \
        -keyout "$ca_dir/ca.key" -out "$ca_dir/ca.crt" >/dev/null 2>&1); then
    echo "OpenSSL could not create the local certificate authority."
    return 1
  fi
  chmod 600 "$ca_dir/ca.key"
  chmod 644 "$ca_dir/ca.crt"
}

# Issues the Nginx certificate from the local CA; it is kept while the names
# and the CA are unchanged and it is valid for more than 30 more days.
ensure_ca_signed_certificate() {
  local san names_file="$PROXY_CERT_DIR/generated-names.txt" csr ext
  ensure_local_ca || return 1
  san="$(server_subject_alt_names)"
  mkdir -p "$PROXY_CERT_DIR"
  if [[ -f "$PROXY_CERT_DIR/fullchain.pem" && -f "$PROXY_CERT_DIR/privkey.pem" &&
        -f "$names_file" && "$(cat "$names_file")" == "$san" ]] &&
     openssl x509 -checkend 2592000 -noout -in "$PROXY_CERT_DIR/fullchain.pem" >/dev/null 2>&1 &&
     openssl verify -CAfile "$PROXY_CA_DIR/ca.crt" "$PROXY_CERT_DIR/fullchain.pem" >/dev/null 2>&1; then
    echo "Reusing the existing HTTPS certificate for $PROXY_SERVER_NAME."
    return 0
  fi
  echo "Issuing the HTTPS certificate for $PROXY_SERVER_NAME from the local certificate authority..."
  csr="$(mktemp)"
  ext="$(mktemp)"
  printf '%s\n' \
    "basicConstraints=critical,CA:FALSE" \
    "keyUsage=critical,digitalSignature,keyEncipherment" \
    "extendedKeyUsage=serverAuth" \
    "subjectAltName=$san" \
    "authorityKeyIdentifier=keyid,issuer" > "$ext"
  # 825 days is the longest validity Apple devices accept for such certificates.
  if ! (umask 077 &&
        openssl req -new -newkey rsa:2048 -nodes -sha256 -subj "/CN=$PROXY_SERVER_NAME" \
          -keyout "$PROXY_CERT_DIR/privkey.pem" -out "$csr" >/dev/null 2>&1 &&
        openssl x509 -req -in "$csr" -CA "$PROXY_CA_DIR/ca.crt" -CAkey "$PROXY_CA_DIR/ca.key" \
          -CAcreateserial -CAserial "$PROXY_CA_DIR/ca.srl" -days 825 -sha256 -extfile "$ext" \
          -out "$PROXY_CERT_DIR/fullchain.pem" >/dev/null 2>&1); then
    rm -f -- "$csr" "$ext"
    echo "OpenSSL could not issue the HTTPS certificate."
    return 1
  fi
  rm -f -- "$csr" "$ext"
  printf '%s' "$san" > "$names_file"
}

# Download page served on the HTTP port: the CA certificate, a one-click
# Windows installer and per-device instructions. Browsers never install a
# trusted root on their own, so each device approves it once.
write_ca_download_page() {
  local public_dir="$PROXY_CONFIG_DIR/public" odoo_url ca_name fingerprint line
  mkdir -p "$public_dir"
  cp -- "$PROXY_CA_DIR/ca.crt" "$public_dir/odoo-local-ca.crt"
  odoo_url="$(proxy_enterprise_url)"
  [[ "$START_ENTERPRISE" == "true" ]] || odoo_url="$(proxy_community_url)"
  ca_name="$(openssl x509 -noout -subject -nameopt multiline -in "$PROXY_CA_DIR/ca.crt" | awk -F' = ' '/commonName/ {print $2}')"
  fingerprint="$(openssl x509 -noout -fingerprint -sha256 -in "$PROXY_CA_DIR/ca.crt" | cut -d= -f2)"

  {
    printf '%s\r\n' '@echo off' \
      'rem Installs the Odoo local certificate authority as a trusted root (Windows).' \
      'net session >nul 2>&1' \
      'if errorlevel 1 (' \
      '  echo Right-click this file and choose "Run as administrator".' \
      '  pause' \
      '  exit /b 1' \
      ')' \
      'set "CERT=%TEMP%\odoo-local-ca.crt"' \
      '('
    while IFS= read -r line; do
      printf 'echo %s\r\n' "$line"
    done < "$PROXY_CA_DIR/ca.crt"
    printf '%s\r\n' ') > "%CERT%"' \
      'certutil -addstore -f Root "%CERT%"' \
      'if errorlevel 1 (' \
      '  echo The certificate could not be installed.' \
      ') else (' \
      "  echo Installed. Close all browser windows, then open $odoo_url" \
      ')' \
      'del "%CERT%" >nul 2>&1' \
      'pause'
  } > "$public_dir/install-odoo-ca.bat"

  cat > "$public_dir/index.html" <<EOF
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Odoo secure access setup</title>
<style>
  body { font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; margin: 0; background: #f4f5f7; color: #1f2933; }
  main { max-width: 760px; margin: 0 auto; padding: 24px 16px 48px; }
  h1 { font-size: 1.6rem; margin: 8px 0 4px; }
  h2 { font-size: 1.15rem; margin: 0 0 10px; }
  .card { background: #fff; border-radius: 10px; padding: 16px 18px; margin: 14px 0; box-shadow: 0 1px 3px rgba(0,0,0,.08); }
  .btn { display: inline-block; padding: 10px 16px; border-radius: 8px; text-decoration: none; font-weight: 600; margin: 4px 8px 4px 0; }
  .primary { background: #714b67; color: #fff; }
  .secondary { background: #e7e9ee; color: #1f2933; }
  ol { padding-left: 20px; } li { margin: 6px 0; }
  code { background: #eef0f3; padding: 2px 5px; border-radius: 4px; font-size: .9em; word-break: break-all; }
  .muted { color: #5f6b7a; font-size: .9rem; }
  .detected { background: #eaf4ea; border-radius: 8px; padding: 10px 14px; margin-top: 12px; }
  [hidden] { display: none !important; }
</style>
</head>
<body>
<main>
  <h1>Odoo secure access</h1>
  <p class="muted">Install the company certificate once on this device so the browser opens Odoo with a normal padlock instead of a "Not secure" warning.</p>
  <p class="detected" id="detected" hidden>
    Showing the steps for <b id="detected-name"></b>.
    <a href="#" id="show-all">Using a different device? Show all</a>
  </p>

  <div class="card" data-os="windows">
    <h2>Windows</h2>
    <a class="btn primary" href="/install-odoo-ca.bat" download>Download the Windows installer</a>
    <ol>
      <li>Open your <b>Downloads</b> folder.</li>
      <li>Right-click <code>install-odoo-ca.bat</code> and choose <b>Run as administrator</b>, then click <b>Yes</b>.</li>
      <li>When it says <i>Installed</i>, close all browser windows and open Odoo again.</li>
    </ol>
    <p class="muted">IT installing many PCs at once: <a href="/odoo-local-ca.crt" download>download the certificate file</a> and deploy it with Group Policy (Computer Configuration → Policies → Windows Settings → Security Settings → Public Key Policies → Trusted Root Certification Authorities → Import).</p>
  </div>

  <div class="card" data-os="macos">
    <h2>macOS</h2>
    <a class="btn primary" href="/odoo-local-ca.crt" download>Download the certificate</a>
    <ol>
      <li>Double-click the downloaded <code>odoo-local-ca.crt</code>; Keychain Access asks where to add it: choose <b>System</b>.</li>
      <li>In Keychain Access, double-click <b>${ca_name}</b> → <b>Trust</b> → "When using this certificate": <b>Always Trust</b>.</li>
      <li>Close the window, enter your Mac password, then reopen the browser.</li>
    </ol>
    <p class="muted">Firefox: Settings → Privacy &amp; Security → Certificates → View Certificates → Authorities → Import, and tick "Trust this CA to identify websites".</p>
  </div>

  <div class="card" data-os="linux">
    <h2>Ubuntu / Linux</h2>
    <a class="btn primary" href="/odoo-local-ca.crt" download>Download the certificate</a>
    <p>Open a terminal in your Downloads folder and run:</p>
    <ol>
      <li>System: <code>sudo cp odoo-local-ca.crt /usr/local/share/ca-certificates/ &amp;&amp; sudo update-ca-certificates</code></li>
      <li>Chrome / Chromium: <code>sudo apt install -y libnss3-tools &amp;&amp; mkdir -p \$HOME/.pki/nssdb &amp;&amp; { [ -f \$HOME/.pki/nssdb/cert9.db ] || certutil -d sql:\$HOME/.pki/nssdb -N --empty-password; } &amp;&amp; certutil -d sql:\$HOME/.pki/nssdb -A -t "C,," -n "Odoo Local CA" -i odoo-local-ca.crt</code></li>
      <li>Firefox: Settings → Privacy &amp; Security → Certificates → View Certificates → Authorities → Import, and tick "Trust this CA to identify websites".</li>
      <li>Close every browser window (<code>pkill -f chrome</code> for Chrome) and open Odoo again.</li>
    </ol>
  </div>

  <div class="card" data-os="android">
    <h2>Android</h2>
    <a class="btn primary" href="/odoo-local-ca.crt" download>Download the certificate</a>
    <ol>
      <li>Open <b>Settings</b> → <b>Security</b> (or Security &amp; privacy) → <b>Encryption &amp; credentials</b> → <b>Install a certificate</b> → <b>CA certificate</b>.</li>
      <li>Tap <b>Install anyway</b> and choose the downloaded <code>odoo-local-ca.crt</code>.</li>
      <li>Open Odoo again in Chrome.</li>
    </ol>
  </div>

  <div class="card" data-os="ios">
    <h2>iPhone / iPad</h2>
    <a class="btn primary" href="/odoo-local-ca.crt" download>Download the certificate</a>
    <ol>
      <li>Open this page in <b>Safari</b>, tap the button and choose <b>Allow</b>.</li>
      <li><b>Settings</b> → <b>General</b> → <b>VPN &amp; Device Management</b> → tap the downloaded profile → <b>Install</b>.</li>
      <li><b>Settings</b> → <b>General</b> → <b>About</b> → <b>Certificate Trust Settings</b> → turn on <b>${ca_name}</b>.</li>
    </ol>
  </div>

  <div class="card">
    <h2>Open Odoo</h2>
    <a class="btn primary" href="${odoo_url}">Open Odoo (${odoo_url})</a>
    <p class="muted">Certificate: <b>${ca_name}</b><br>SHA-256 fingerprint: <code>${fingerprint}</code></p>
  </div>
</main>
<script>
(function () {
  var ua = navigator.userAgent || "";
  var platform = (navigator.userAgentData && navigator.userAgentData.platform) || navigator.platform || "";
  var os = null;
  if (/android/i.test(ua)) os = "android";
  else if (/iphone|ipad|ipod/i.test(ua) || (/mac/i.test(platform) && navigator.maxTouchPoints > 1)) os = "ios";
  else if (/win/i.test(platform) || /windows/i.test(ua)) os = "windows";
  else if (/mac/i.test(platform) || /mac os x/i.test(ua)) os = "macos";
  else if (/linux|x11|cros/i.test(platform + " " + ua)) os = "linux";
  if (!os) return;
  var names = { windows: "Windows", macos: "macOS", linux: "Ubuntu / Linux", android: "Android", ios: "iPhone / iPad" };
  var cards = document.querySelectorAll("[data-os]");
  for (var i = 0; i < cards.length; i++) cards[i].hidden = cards[i].getAttribute("data-os") !== os;
  document.getElementById("detected-name").textContent = names[os];
  document.getElementById("detected").hidden = false;
  document.getElementById("show-all").addEventListener("click", function (event) {
    event.preventDefault();
    for (var j = 0; j < cards.length; j++) cards[j].hidden = false;
    document.getElementById("detected").hidden = true;
  });
})();
</script>
</body>
</html>
EOF
  chmod 644 "$public_dir"/*
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
  rm -f -- "$PROXY_CERT_DIR/generated-names.txt" "$PROXY_CERT_DIR/self-signed-names.txt"
}

# One HTTPS server block proxying to an Odoo service. With workers, Odoo serves
# websockets on its evented port 8072; in threaded mode on 8069 itself.
nginx_odoo_server_block() {
  local listen_port="$1" service="$2" workers="$3" tls="${4:-true}" chat_port=8069
  (( workers > 0 )) && chat_port=8072
  if [[ "$tls" == "true" ]]; then
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
EOF
  else
    cat <<EOF
server {
    listen $listen_port$([[ "$listen_port" == "80" ]] && echo " default_server");
    server_name _;

    location = /nginx-health {
        access_log off;
        return 200 "ok\n";
    }
EOF
  fi
  cat <<EOF

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

EOF
    if [[ "$PROXY_CERT_MODE" == "none" ]]; then
      write_nginx_http_only_servers
    else
      cat <<EOF
# Plain HTTP redirects to HTTPS and answers the container health check. With
# the local certificate authority, its root page offers the CA certificate.
server {
    listen 80 default_server;
    server_name _;

    location = /nginx-health {
        access_log off;
        return 200 "ok\n";
    }
EOF
      if [[ "$PROXY_CERT_MODE" == "local-ca" ]]; then
        cat <<'EOF'

    root /usr/share/nginx/odoo-ca;

    location = / {
        try_files /index.html =404;
    }

    location = /odoo-local-ca.crt {
        types { }
        default_type application/x-x509-ca-cert;
        add_header Content-Disposition 'attachment; filename="odoo-local-ca.crt"';
    }

    location = /install-odoo-ca.bat {
        types { }
        default_type application/octet-stream;
        add_header Content-Disposition 'attachment; filename="install-odoo-ca.bat"';
    }
EOF
      fi
      cat <<EOF

    location / {
        return 301 $(proxy_url "$redirect_port")\$request_uri;
    }
}

EOF
      if [[ "$START_ENTERPRISE" == "true" ]]; then
        echo "# Odoo Enterprise: $(proxy_enterprise_url)"
        nginx_odoo_server_block "$PROXY_CONTAINER_ENTERPRISE_PORT" enterprise "$ENTERPRISE_WORKERS"
      fi
      if [[ "$START_COMMUNITY" == "true" ]]; then
        echo "# Odoo Community: $(proxy_community_url)"
        nginx_odoo_server_block "$PROXY_CONTAINER_COMMUNITY_PORT" community "$COMMUNITY_WORKERS"
      fi
    fi
  } > "$conf_dir/odoo.conf"
}

# HTTP only: container port 80 serves the first selected edition and 9443
# serves Community. Every published listener answers, so no port is left dead.
write_nginx_http_only_servers() {
  local main_service=community main_workers="$COMMUNITY_WORKERS"
  if [[ "$START_ENTERPRISE" == "true" ]]; then
    main_service=enterprise
    main_workers="$ENTERPRISE_WORKERS"
  fi
  echo "# Odoo ${main_service^}: $(proxy_url "$PROXY_HTTP_PORT")"
  nginx_odoo_server_block 80 "$main_service" "$main_workers" false
  # Published on 127.0.0.1 only in HTTP mode (PROXY_TLS_BIND_ADDRESS).
  nginx_odoo_server_block "$PROXY_CONTAINER_ENTERPRISE_PORT" "$main_service" "$main_workers" false
  if [[ "$START_COMMUNITY" == "true" ]]; then
    echo "# Odoo Community: $(proxy_community_url)"
    nginx_odoo_server_block "$PROXY_CONTAINER_COMMUNITY_PORT" community "$COMMUNITY_WORKERS" false
  else
    nginx_odoo_server_block "$PROXY_CONTAINER_COMMUNITY_PORT" "$main_service" "$main_workers" false
  fi
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
