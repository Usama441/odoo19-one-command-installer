#!/usr/bin/env bash
# Sourced by install-ubuntu.sh -- not meant to run standalone.

# The review stays open until the installation succeeds or the user cancels:
# settings can be changed here, and a failed install stage (image download,
# certificate, Nginx check, container start) returns here instead of exiting.
step_review_and_install() {
  local choice show_plan="true"
  INSTALL_FAILURE=""
  while true; do
    # After a failure the plan is not reprinted, so the error stays on screen.
    if [[ "$show_plan" == "true" ]]; then
      section "5/6" "Review the installation plan"
      print_install_plan
    fi
    echo
    if [[ -n "$INSTALL_FAILURE" ]]; then
      printf '%b\n' "${COLOR_RED}${COLOR_BOLD}The installation stopped: $INSTALL_FAILURE${COLOR_RESET}"
      echo "Fix the problem shown above, then try again or change a setting. Your answers are kept."
      echo "  1) Try the installation again"
      echo "  2) Change a setting"
      echo "  3) Exit"
    else
      echo "  1) Start the installation now"
      echo "  2) Change a setting"
      echo "  3) Cancel"
    fi
    read_choice choice "Choose an option [1]: " "" "1 2 3"
    case "$choice" in
      1)
        INSTALL_FAILURE=""
        run_installation
        [[ -z "$INSTALL_FAILURE" ]] && return
        show_plan="false"
        ;;
      2)
        change_install_setting
        show_plan="true"
        ;;
      3)
        if [[ -n "$INSTALL_FAILURE" ]]; then
          echo "Installation stopped. The settings written so far are kept in .env; run the installer again to finish."
        else
          echo "Installation cancelled. No Odoo configuration or Enterprise addons were changed."
        fi
        exit 0
        ;;
    esac
  done
}

# Re-asks one group of settings, then the review shows the updated plan.
change_install_setting() {
  local choice
  echo
  echo "Which settings do you want to change?"
  echo "  1) Profile, network address and Nginx on/off (asks steps 2 to 4 again)"
  echo "  2) Custom addons folder"
  echo "  3) pgAdmin"
  echo "  4) Nginx address, certificate and ports"
  echo "  5) Back to the plan"
  read_choice choice "Choose an option [5]: " "" "1 2 3 4 5"
  case "$choice" in
    1)
      # Later steps depend on these answers (ports, workers, pgAdmin), so they
      # are asked again in order.
      step_choose_deployment_mode
      step_prepare_edition
      step_configure_pgadmin
      step_configure_proxy
      ;;
    2) configure_custom_addons_directory "$ODOO_HOST_CUSTOM_ADDONS_DIR" ;;
    3)
      step_configure_pgadmin
      if [[ "$PROXY_ENABLED" == "true" && "$PGADMIN_ENABLED" == "true" ]] &&
         [[ "$PGADMIN_PORT" == "$PROXY_HTTP_PORT" || "$PGADMIN_PORT" == "$ENTERPRISE_HTTPS_PORT" ||
            "$PGADMIN_PORT" == "$COMMUNITY_HTTPS_PORT" ]]; then
        echo "pgAdmin port $PGADMIN_PORT is also an Nginx port, so the Nginx settings are asked again."
        step_configure_proxy
      fi
      ;;
    4)
      if [[ "$PROXY_ENABLED" == "true" ]]; then
        step_configure_proxy
      else
        echo "Nginx is not selected. Use option 1 to turn it on."
      fi
      ;;
  esac
}

# Prints a fix when Docker's credential helper (often left behind by Docker
# Desktop as "credsStore": "desktop") is missing, which breaks every pull.
docker_credential_helper_hint() {
  local config="$HOME/.docker/config.json" helper
  [[ -r "$config" ]] || return 0
  helper="$(sed -n 's/.*"credsStore"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$config" | head -n 1)"
  if [[ -n "$helper" ]] && ! command -v "docker-credential-$helper" >/dev/null 2>&1; then
    echo
    printf '%b\n' "${COLOR_YELLOW}$config asks Docker to use the credential helper docker-credential-$helper, which is not installed.${COLOR_RESET}"
    echo "This is usually left behind by Docker Desktop. In another terminal, remove that line:"
    echo "  cp $config $config.bak"
    echo "  sed -i '/\"credsStore\"/d' $config"
    echo "Then choose 1 to try again."
  fi
}

print_install_plan() {
  printf '  %-24s %s\n' "Odoo version" "$ODOO_VERSION ($ODOO_IMAGE)"
  printf '  %-24s %s\n' "Profile" "$DEPLOYMENT_MODE"
  printf '  %-24s %s\n' "Performance mode" "$PERFORMANCE_MODE"
  printf '  %-24s %s\n' "Network exposure" "$(bind_address_label)"
  if [[ "$START_COMMUNITY" == "true" ]]; then
    if [[ "$PROXY_ENABLED" == "true" ]]; then
      printf '  %-24s %s\n' "Community" "enabled; internal port $COMMUNITY_PORT behind Nginx"
    else
      printf '  %-24s %s\n' "Community" "enabled on port $COMMUNITY_PORT"
    fi
    printf '  %-24s %s\n' "Community custom addons" "$ODOO_HOST_CUSTOM_ADDONS_DIR"
    if [[ "$DEPLOYMENT_MODE" == "production" ]]; then
      printf '  %-24s %s\n' "Community workers" "$COMMUNITY_WORKERS (~$((COMMUNITY_WORKERS * 6)) simultaneous users)"
    else
      printf '  %-24s %s\n' "Community server" "threaded testing mode (workers = 0)"
    fi
  else
    printf '  %-24s %s\n' "Community" "not selected"
  fi
  if [[ "$START_ENTERPRISE" == "true" ]]; then
    if [[ "$PROXY_ENABLED" == "true" ]]; then
      printf '  %-24s %s\n' "Enterprise" "enabled; internal port $ENTERPRISE_PORT behind Nginx"
    else
      printf '  %-24s %s\n' "Enterprise" "enabled on port $ENTERPRISE_PORT"
    fi
    printf '  %-24s %s\n' "Enterprise storage" "$ODOO_HOST_ENTERPRISE_DIR"
    printf '  %-24s %s\n' "Enterprise custom addons" "$ODOO_HOST_CUSTOM_ADDONS_DIR"
    if [[ "$DEPLOYMENT_MODE" == "production" ]]; then
      printf '  %-24s %s\n' "Enterprise workers" "$ENTERPRISE_WORKERS (~$((ENTERPRISE_WORKERS * 6)) simultaneous users)"
    else
      printf '  %-24s %s\n' "Enterprise server" "threaded testing mode (workers = 0)"
    fi
    if [[ -n "$ENTERPRISE_SOURCE" ]]; then
      printf '  %-24s %s\n' "Enterprise addons" "import from $ENTERPRISE_SOURCE"
    else
      printf '  %-24s %s\n' "Enterprise addons" "reuse installed addons"
    fi
  else
    printf '  %-24s %s\n' "Enterprise" "not selected"
  fi
  if [[ "$PGADMIN_ENABLED" == "true" ]]; then
    printf '  %-24s %s\n' "pgAdmin" "enabled on port $PGADMIN_PORT"
    printf '  %-24s %s\n' "pgAdmin login" "$PGADMIN_EMAIL"
  else
    printf '  %-24s %s\n' "pgAdmin" "not selected"
  fi
  if [[ "$PROXY_ENABLED" == "true" ]]; then
    printf '  %-24s %s\n' "Reverse proxy" "$(proxy_mode_label)"
    if [[ "$START_ENTERPRISE" == "true" ]]; then
      printf '  %-24s %s\n' "Enterprise URL" "$(proxy_enterprise_url)"
    fi
    if [[ "$START_COMMUNITY" == "true" ]]; then
      printf '  %-24s %s\n' "Community URL" "$(proxy_community_url)"
    fi
    printf '  %-24s %s\n' "Odoo internal ports" "127.0.0.1 only; users open the URLs above"
  else
    printf '  %-24s %s\n' "Reverse proxy" "not selected"
  fi
  printf '  %-24s %s\n' "Cron threads" "$ODOO_MAX_CRON_THREADS per selected edition"
  if [[ "$DEPLOYMENT_MODE" == "production" ]]; then
    printf '  %-24s %s\n' "Worker memory limits" "$((ODOO_LIMIT_MEMORY_SOFT / 1024 / 1024)) MiB soft / $((ODOO_LIMIT_MEMORY_HARD / 1024 / 1024)) MiB hard"
  fi
  printf '  %-24s %s\n' "Automatic restart" "enabled"
}

# Runs the installation. A failed stage sets INSTALL_FAILURE and returns 0, so
# set -e stays active for everything else in this function.
run_installation() {
  prepare_persistent_addons_layout
  migrate_legacy_custom_addons

  if [[ -n "$ENTERPRISE_SOURCE" &&
        "$(realpath "$ENTERPRISE_SOURCE")" != "$(realpath "$ODOO_HOST_ENTERPRISE_DIR")" ]]; then
    echo "Copying Enterprise addons into $ODOO_HOST_ENTERPRISE_DIR. This may take a moment..."
    cp -a "$ENTERPRISE_SOURCE"/. "$ODOO_HOST_ENTERPRISE_DIR/"
    # A retry from the review reuses the copy instead of copying again.
    ENTERPRISE_SOURCE=""
  fi
  sudo chmod -R u+rwX,go+rX "$ODOO_HOST_CUSTOM_ADDONS_DIR"
  if [[ "$START_ENTERPRISE" == "true" ]]; then
    sudo chmod -R u+rwX,go+rX "$ODOO_HOST_ENTERPRISE_DIR"
  fi

  echo "Generating private configuration and credentials..."
  if [[ ! "$NGINX_IMAGE" =~ ^[A-Za-z0-9][A-Za-z0-9._/@:-]+$ ]]; then
    echo "The Nginx image reference in .env is invalid."
    exit 1
  fi
  # Behind the proxy only Nginx is published; Odoo stays reachable on localhost.
  ODOO_BIND_ADDRESS="$BIND_ADDRESS"
  [[ "$PROXY_ENABLED" == "true" ]] && ODOO_BIND_ADDRESS="127.0.0.1"
  PROXY_TLS_BIND_ADDRESS="$BIND_ADDRESS"
  [[ "$PROXY_CERT_MODE" == "none" ]] && PROXY_TLS_BIND_ADDRESS="127.0.0.1"

  umask 077
  cat > .env <<EOF
ODOO_VERSION=$ODOO_VERSION
ODOO_IMAGE=$ODOO_IMAGE
POSTGRES_IMAGE=$POSTGRES_IMAGE
PGADMIN_IMAGE=$PGADMIN_IMAGE
BIND_ADDRESS=$BIND_ADDRESS
ODOO_BIND_ADDRESS=$ODOO_BIND_ADDRESS
COMMUNITY_PORT=$COMMUNITY_PORT
ENTERPRISE_PORT=$ENTERPRISE_PORT
COMMUNITY_DB_PASSWORD=$COMMUNITY_DB_PASSWORD
ENTERPRISE_DB_PASSWORD=$ENTERPRISE_DB_PASSWORD
COMMUNITY_ADMIN_PASSWORD=$COMMUNITY_ADMIN_PASSWORD
ENTERPRISE_ADMIN_PASSWORD=$ENTERPRISE_ADMIN_PASSWORD
PGADMIN_ENABLED=$PGADMIN_ENABLED
PGADMIN_PORT=$PGADMIN_PORT
PGADMIN_EMAIL=$PGADMIN_EMAIL
PGADMIN_PASSWORD=$PGADMIN_PASSWORD
PERFORMANCE_MODE=$PERFORMANCE_MODE
COMMUNITY_EXPECTED_USERS=$COMMUNITY_EXPECTED_USERS
ENTERPRISE_EXPECTED_USERS=$ENTERPRISE_EXPECTED_USERS
COMMUNITY_WORKERS=$COMMUNITY_WORKERS
ENTERPRISE_WORKERS=$ENTERPRISE_WORKERS
ODOO_MAX_CRON_THREADS=$ODOO_MAX_CRON_THREADS
ODOO_LIMIT_MEMORY_SOFT=$ODOO_LIMIT_MEMORY_SOFT
ODOO_LIMIT_MEMORY_HARD=$ODOO_LIMIT_MEMORY_HARD
COMMUNITY_CUSTOM_ADDONS_PATH=$ODOO_HOST_CUSTOM_ADDONS_DIR
ENTERPRISE_ADDONS_PATH=$ODOO_HOST_ENTERPRISE_DIR
ENTERPRISE_CUSTOM_ADDONS_PATH=$ODOO_HOST_CUSTOM_ADDONS_DIR
PROXY_ENABLED=$PROXY_ENABLED
PROXY_CERT_MODE=$PROXY_CERT_MODE
PROXY_SERVER_NAME=$PROXY_SERVER_NAME
PROXY_HTTP_PORT=$PROXY_HTTP_PORT
PROXY_TLS_BIND_ADDRESS=$PROXY_TLS_BIND_ADDRESS
ENTERPRISE_HTTPS_PORT=$ENTERPRISE_HTTPS_PORT
COMMUNITY_HTTPS_PORT=$COMMUNITY_HTTPS_PORT
NGINX_IMAGE=$NGINX_IMAGE
EOF

  write_config config/community/odoo.conf db-community "$COMMUNITY_DB_PASSWORD" "$COMMUNITY_ADMIN_PASSWORD" \
    "/usr/lib/python3/dist-packages/odoo/addons,/mnt/extra-addons" \
    "$COMMUNITY_WORKERS" "$ODOO_MAX_CRON_THREADS" "$ODOO_LIMIT_MEMORY_SOFT" "$ODOO_LIMIT_MEMORY_HARD"
  write_config config/enterprise/odoo.conf db-enterprise "$ENTERPRISE_DB_PASSWORD" "$ENTERPRISE_ADMIN_PASSWORD" \
    "/mnt/enterprise-addons,/usr/lib/python3/dist-packages/odoo/addons,/mnt/extra-addons" \
    "$ENTERPRISE_WORKERS" "$ODOO_MAX_CRON_THREADS" "$ODOO_LIMIT_MEMORY_SOFT" "$ODOO_LIMIT_MEMORY_HARD"

  if [[ "$START_COMMUNITY" == "true" && "$START_ENTERPRISE" == "true" ]]; then
    cat > config/pgadmin/servers.json <<EOF
{
  "Servers": {
    "1": {
      "Name": "Odoo $ODOO_MAJOR_VERSION Community PostgreSQL",
      "Group": "Odoo $ODOO_MAJOR_VERSION",
      "Host": "db-community",
      "Port": 5432,
      "MaintenanceDB": "postgres",
      "Username": "odoo",
      "SSLMode": "prefer"
    },
    "2": {
      "Name": "Odoo $ODOO_MAJOR_VERSION Enterprise PostgreSQL",
      "Group": "Odoo $ODOO_MAJOR_VERSION",
      "Host": "db-enterprise",
      "Port": 5432,
      "MaintenanceDB": "postgres",
      "Username": "odoo",
      "SSLMode": "prefer"
    }
  }
}
EOF
  elif [[ "$START_ENTERPRISE" == "true" ]]; then
    cat > config/pgadmin/servers.json <<EOF
{
  "Servers": {
    "1": {
      "Name": "Odoo $ODOO_MAJOR_VERSION Enterprise PostgreSQL",
      "Group": "Odoo $ODOO_MAJOR_VERSION",
      "Host": "db-enterprise",
      "Port": 5432,
      "MaintenanceDB": "postgres",
      "Username": "odoo",
      "SSLMode": "prefer"
    }
  }
}
EOF
  else
    cat > config/pgadmin/servers.json <<EOF
{
  "Servers": {
    "1": {
      "Name": "Odoo $ODOO_MAJOR_VERSION Community PostgreSQL",
      "Group": "Odoo $ODOO_MAJOR_VERSION",
      "Host": "db-community",
      "Port": 5432,
      "MaintenanceDB": "postgres",
      "Username": "odoo",
      "SSLMode": "prefer"
    }
  }
}
EOF
  fi
  cat > config/pgadmin/pgpass <<EOF
db-community:5432:*:odoo:$COMMUNITY_DB_PASSWORD
db-enterprise:5432:*:odoo:$ENTERPRISE_DB_PASSWORD
EOF
  chmod 600 .env config/community/odoo.conf config/enterprise/odoo.conf config/pgadmin/servers.json config/pgadmin/pgpass

  if [[ "$PROXY_ENABLED" == "true" ]]; then
    if [[ "$PROXY_CERT_MODE" == "custom" ]]; then
      if [[ -n "$PROXY_CUSTOM_CERT" ]]; then
        if ! install_custom_certificate "$PROXY_CUSTOM_CERT" "$PROXY_CUSTOM_KEY"; then
          INSTALL_FAILURE="the certificate files could not be installed for Nginx."
          return 0
        fi
      elif [[ ! -f "$PROXY_CERT_DIR/fullchain.pem" || ! -f "$PROXY_CERT_DIR/privkey.pem" ]]; then
        INSTALL_FAILURE="no certificate is installed for Nginx. Choose 2, then 4, to provide the certificate files."
        return 0
      fi
    elif [[ "$PROXY_CERT_MODE" == "local-ca" ]]; then
      if ! ensure_ca_signed_certificate; then
        INSTALL_FAILURE="the company CA certificate could not be created."
        return 0
      fi
    fi
    mkdir -p "$PROXY_CERT_DIR" "$PROXY_CONFIG_DIR/public"
    rm -f -- "$PROXY_CONFIG_DIR/public/"*
    if [[ "$PROXY_CERT_MODE" == "local-ca" ]]; then
      write_ca_download_page
    fi
    write_nginx_config
    chmod 700 "$PROXY_CERT_DIR"
    chmod 600 "$PROXY_CERT_DIR"/*.pem 2>/dev/null || true
  fi

  COMPOSE_PROFILE=()
  if [[ "$PGADMIN_ENABLED" == "true" ]]; then COMPOSE_PROFILE+=(--profile pgadmin); fi
  if [[ "$PROXY_ENABLED" == "true" ]]; then COMPOSE_PROFILE+=(--profile proxy); fi
  echo "Downloading the required Docker images..."
  if ! "${DOCKER[@]}" compose "${COMPOSE_PROFILE[@]}" pull; then
    docker_credential_helper_hint
    INSTALL_FAILURE="the Docker images could not be downloaded."
    return 0
  fi
  if ! verify_install_addon_mounts; then
    INSTALL_FAILURE="the Odoo containers cannot read the addons folders."
    return 0
  fi
  if [[ "$PROXY_ENABLED" == "true" ]] && ! verify_nginx_config; then
    INSTALL_FAILURE="the generated Nginx configuration did not pass its check."
    return 0
  fi

  # Keep the configuration private from other host users while making it readable
  # by the non-root odoo user in the official container image.
  ODOO_CONTAINER_GID="$("${DOCKER[@]}" run --rm --entrypoint id "$ODOO_IMAGE" -g)"
  if [[ "$ODOO_CONTAINER_GID" =~ ^[0-9]+$ ]]; then
    sudo chgrp "$ODOO_CONTAINER_GID" config/community/odoo.conf config/enterprise/odoo.conf
    chmod 640 config/community/odoo.conf config/enterprise/odoo.conf
  fi
  if ! "${DOCKER[@]}" run --rm --entrypoint /bin/sh \
      -v "$SCRIPT_DIR/config/community/odoo.conf:/tmp/odoo.conf:ro" \
      "$ODOO_IMAGE" -c 'test -r /tmp/odoo.conf'; then
    echo "Warning: using mode 644 for Odoo configuration because this Docker setup remaps container users."
    chmod 644 config/community/odoo.conf config/enterprise/odoo.conf
  fi

  if [[ "$PGADMIN_ENABLED" == "true" ]]; then
    if ! "${DOCKER[@]}" run --rm --entrypoint /bin/sh \
        -v "$SCRIPT_DIR/config/pgadmin/pgpass:/tmp/pgpass:ro" \
        "$PGADMIN_IMAGE" -c 'test -r /tmp/pgpass'; then
      PGADMIN_CONTAINER_GID="$("${DOCKER[@]}" run --rm --entrypoint id "$PGADMIN_IMAGE" -g)"
      if [[ ! "$PGADMIN_CONTAINER_GID" =~ ^[0-9]+$ ]]; then
        echo "Could not determine the pgAdmin container group."
        exit 1
      fi
      sudo chgrp "$PGADMIN_CONTAINER_GID" config/pgadmin/servers.json config/pgadmin/pgpass
      chmod 640 config/pgadmin/servers.json config/pgadmin/pgpass
      if ! "${DOCKER[@]}" run --rm --entrypoint /bin/sh \
          -v "$SCRIPT_DIR/config/pgadmin/pgpass:/tmp/pgpass:ro" \
          "$PGADMIN_IMAGE" -c 'test -r /tmp/pgpass'; then
        echo "pgAdmin cannot securely read its generated password file on this Docker setup."
        exit 1
      fi
    fi
  fi

  if [[ "$START_COMMUNITY" != "true" ]] &&
     { [[ -n "$("${DOCKER[@]}" compose ps -q community)" ]] ||
       [[ -n "$("${DOCKER[@]}" compose ps -q db-community)" ]]; }; then
    echo "Stopping the previously running Community services because they were not selected..."
    "${DOCKER[@]}" compose stop community db-community
  fi
  if [[ "$START_ENTERPRISE" != "true" ]] &&
     { [[ -n "$("${DOCKER[@]}" compose ps -q enterprise)" ]] ||
       [[ -n "$("${DOCKER[@]}" compose ps -q db-enterprise)" ]]; }; then
    echo "Stopping the previously running Enterprise services because they were not selected..."
    "${DOCKER[@]}" compose stop enterprise db-enterprise
  fi
  if [[ "$PGADMIN_ENABLED" != "true" ]] &&
     [[ -n "$("${DOCKER[@]}" compose --profile pgadmin ps -q pgadmin)" ]]; then
    echo "Stopping pgAdmin because it was not selected..."
    "${DOCKER[@]}" compose --profile pgadmin stop pgadmin
  fi
  if [[ "$PROXY_ENABLED" != "true" ]] &&
     [[ -n "$("${DOCKER[@]}" compose --profile proxy ps -q nginx)" ]]; then
    echo "Stopping the Nginx HTTPS proxy because it was not selected..."
    "${DOCKER[@]}" compose --profile proxy stop nginx
  fi
  START_SERVICES=()
  if [[ "$START_COMMUNITY" == "true" ]]; then START_SERVICES+=(db-community community); fi
  if [[ "$START_ENTERPRISE" == "true" ]]; then START_SERVICES+=(db-enterprise enterprise); fi
  if [[ "$PGADMIN_ENABLED" == "true" ]]; then START_SERVICES+=(pgadmin); fi
  if ! "${DOCKER[@]}" compose "${COMPOSE_PROFILE[@]}" up -d --wait --wait-timeout 300 "${START_SERVICES[@]}"; then
    INSTALL_FAILURE="the Odoo containers did not start. Check them with: docker compose ps"
    return 0
  fi
  if [[ "$PROXY_ENABLED" == "true" ]]; then
    # Recreate so a rerun always picks up the regenerated configuration and certificate.
    echo "Starting the Nginx reverse proxy..."
    if ! "${DOCKER[@]}" compose "${COMPOSE_PROFILE[@]}" up -d --wait --wait-timeout 120 --force-recreate nginx; then
      INSTALL_FAILURE="the Nginx reverse proxy did not start. Check it with: docker compose logs nginx"
      return 0
    fi
  fi
  if [[ "$PROXY_ENABLED" == "true" && "$PROXY_CERT_MODE" == "local-ca" ]]; then
    certificate_renewal_timer_enabled || enable_certificate_renewal_timer || true
  else
    disable_certificate_renewal_timer
  fi

  if [[ "$BIND_ADDRESS" != "127.0.0.1" ]] &&
     command -v ufw >/dev/null 2>&1 && sudo ufw status | grep -q '^Status: active'; then
    if [[ "$PROXY_ENABLED" == "true" ]]; then
      sudo ufw allow "${PROXY_HTTP_PORT}/tcp"
      if [[ "$START_ENTERPRISE" == "true" && "$PROXY_CERT_MODE" != "none" ]]; then
        sudo ufw allow "${ENTERPRISE_HTTPS_PORT}/tcp"
      fi
      if [[ "$START_COMMUNITY" == "true" ]] &&
         [[ "$PROXY_CERT_MODE" != "none" || "$START_ENTERPRISE" == "true" ]]; then
        sudo ufw allow "${COMMUNITY_HTTPS_PORT}/tcp"
      fi
    else
      if [[ "$START_COMMUNITY" == "true" ]]; then
        sudo ufw allow "${COMMUNITY_PORT}/tcp"
      fi
      if [[ "$START_ENTERPRISE" == "true" ]]; then
        sudo ufw allow "${ENTERPRISE_PORT}/tcp"
      fi
    fi
    if [[ "$PGADMIN_ENABLED" == "true" ]]; then
      sudo ufw allow "${PGADMIN_PORT}/tcp"
    fi
  fi

  HOST_IP="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
  HOST_IP="${HOST_IP:-127.0.0.1}"
  if [[ -z "$ACCESS_HOST" ]]; then
    ACCESS_HOST="$HOST_IP"
  fi
  COMMUNITY_URL="http://$ACCESS_HOST:$COMMUNITY_PORT"
  ENTERPRISE_URL="http://$ACCESS_HOST:$ENTERPRISE_PORT"
  if [[ "$PROXY_ENABLED" == "true" ]]; then
    COMMUNITY_URL="$(proxy_community_url)"
    ENTERPRISE_URL="$(proxy_enterprise_url)"
  fi
  if [[ -e installation-info.txt ]]; then
    chmod 600 installation-info.txt
  fi
  PROXY_SUMMARY="not enabled"
  if [[ "$PROXY_ENABLED" == "true" ]]; then
    PROXY_SUMMARY="$(proxy_mode_label); Odoo ports on 127.0.0.1"
  fi
  (
  umask 077
  {
  cat <<EOF
Odoo version: $ODOO_VERSION
Mode: $DEPLOYMENT_MODE
Performance mode: $PERFORMANCE_MODE
Network binding: $BIND_ADDRESS
Reverse proxy: $PROXY_SUMMARY
Detected hardware: $SYSTEM_SPEC_SUMMARY
Cron threads per selected edition: $ODOO_MAX_CRON_THREADS
Automatic startup: enabled (Docker at boot; containers restart unless manually stopped)
EOF
  if [[ "$DEPLOYMENT_MODE" == "production" ]]; then
  cat <<EOF
Worker memory limits: $((ODOO_LIMIT_MEMORY_SOFT / 1024 / 1024)) MiB soft / $((ODOO_LIMIT_MEMORY_HARD / 1024 / 1024)) MiB hard
EOF
  fi
  if [[ "$START_COMMUNITY" == "true" ]]; then
  cat <<EOF
Community: $COMMUNITY_URL
Community Odoo master password: $COMMUNITY_ADMIN_PASSWORD
EOF
  if [[ "$DEPLOYMENT_MODE" == "production" ]]; then
  cat <<EOF
Community expected simultaneous users: $COMMUNITY_EXPECTED_USERS
Community workers: $COMMUNITY_WORKERS (estimated $((COMMUNITY_WORKERS * 6)) simultaneous users)
EOF
  else
    echo "Community server: threaded testing mode (workers = 0)"
  fi
  else
    echo "Community: not started"
  fi
  if [[ "$START_ENTERPRISE" == "true" ]]; then
  cat <<EOF
Enterprise: $ENTERPRISE_URL
Enterprise Odoo master password: $ENTERPRISE_ADMIN_PASSWORD
EOF
  if [[ "$DEPLOYMENT_MODE" == "production" ]]; then
  cat <<EOF
Enterprise expected simultaneous users: $ENTERPRISE_EXPECTED_USERS
Enterprise workers: $ENTERPRISE_WORKERS (estimated $((ENTERPRISE_WORKERS * 6)) simultaneous users)
EOF
  else
    echo "Enterprise server: threaded testing mode (workers = 0)"
  fi
  else
    echo "Enterprise: not started"
  fi
  if [[ "$PGADMIN_ENABLED" == "true" ]]; then
  cat <<EOF
pgAdmin: http://$ACCESS_HOST:$PGADMIN_PORT
pgAdmin login email: $PGADMIN_EMAIL
pgAdmin login password: $PGADMIN_PASSWORD
EOF
  else
    echo "pgAdmin: not started"
  fi
  cat <<EOF
Odoo image: $ODOO_IMAGE
PostgreSQL image: $POSTGRES_IMAGE
Enterprise addons path: $ODOO_HOST_ENTERPRISE_DIR
Shared custom addons path: $ODOO_HOST_CUSTOM_ADDONS_DIR
EOF
  if [[ "$PGADMIN_ENABLED" == "true" ]]; then echo "pgAdmin image: $PGADMIN_IMAGE"; fi
  if [[ "$PROXY_ENABLED" == "true" ]]; then echo "Nginx image: $NGINX_IMAGE"; fi
  if [[ "$PROXY_ENABLED" == "true" && "$PROXY_CERT_MODE" == "local-ca" ]]; then
    echo "Certificate setup page for each device: $(proxy_ca_page_url)"
  fi
  } > installation-info.txt
  )
  chmod 600 .env installation-info.txt
}
