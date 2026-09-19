#!/usr/bin/env bash
# Sourced by install-ubuntu.sh -- not meant to run standalone.

step_prepare_edition() {
  section "3/6" "Prepare the selected Odoo edition"
  ENTERPRISE_SOURCE=""
  BUNDLED_ENTERPRISE_SOURCE=""
  for candidate in \
    "$ODOO_HOST_ENTERPRISE_DIR" \
    "$SCRIPT_DIR/addons/enterprise" \
    "$SCRIPT_DIR/enterprise-19.0" \
    "$SCRIPT_DIR/enterprise"; do
    if has_enterprise_addons "$candidate" && [[ -f "$candidate/web_enterprise/__manifest__.py" ]]; then
      BUNDLED_ENTERPRISE_SOURCE="$candidate"
      break
    fi
  done

  if [[ "$START_ENTERPRISE" == "true" ]]; then
    if has_enterprise_addons "$ODOO_HOST_ENTERPRISE_DIR" &&
       [[ -f "$ODOO_HOST_ENTERPRISE_DIR/web_enterprise/__manifest__.py" ]]; then
      echo "Reusing the complete Enterprise addons already installed in $ODOO_HOST_ENTERPRISE_DIR."
    elif [[ -n "$BUNDLED_ENTERPRISE_SOURCE" ]]; then
      ENTERPRISE_SOURCE="$BUNDLED_ENTERPRISE_SOURCE"
      echo "Complete Enterprise addons were detected automatically:"
      printf '  %b%s%b\n' "$COLOR_GREEN" "$ENTERPRISE_SOURCE" "$COLOR_RESET"
    else
      echo "Enterprise requires your licensed Odoo 19 Enterprise addon folder."
      read_enterprise_source ""
    fi
  else
    echo "Community-only installation selected; no licensed Enterprise files are required."
  fi

  if [[ "$START_ENTERPRISE" == "true" ]]; then
    while true; do
      read -r -p "Enterprise web port [8070]: " ENTERPRISE_PORT
      ENTERPRISE_PORT="${ENTERPRISE_PORT:-8070}"
      if ! valid_port "$ENTERPRISE_PORT"; then
        echo "Please enter a port number from 1 to 65535."
        continue
      fi
      ENTERPRISE_PORT="$((10#$ENTERPRISE_PORT))"
      if [[ "$START_COMMUNITY" == "true" && "$COMMUNITY_PORT" == "$ENTERPRISE_PORT" ]]; then
        echo "Community and Enterprise need different web ports."
        continue
      fi
      break
    done
  fi

  ODOO_IMAGE="odoo:19.0-20260908"
  POSTGRES_IMAGE="postgres:15.19"
  PGADMIN_IMAGE="dpage/pgadmin4:9.17"
  PGADMIN_ENABLED="false"
  PGADMIN_PORT="5050"
  PGADMIN_EMAIL="admin@example.com"
  PGADMIN_CREDENTIALS_MISSING="false"
  SAVED_PERFORMANCE_MODE=""
  SAVED_COMMUNITY_EXPECTED_USERS=""
  SAVED_ENTERPRISE_EXPECTED_USERS=""
  SAVED_COMMUNITY_WORKERS=""
  SAVED_ENTERPRISE_WORKERS=""
  SAVED_ODOO_MAX_CRON_THREADS=""
  SAVED_ODOO_LIMIT_MEMORY_SOFT=""
  SAVED_ODOO_LIMIT_MEMORY_HARD=""
  SAVED_CUSTOM_ADDONS_PATH=""
  if [[ -f .env ]]; then
    COMMUNITY_DB_PASSWORD="$(get_env_value COMMUNITY_DB_PASSWORD)"
    ENTERPRISE_DB_PASSWORD="$(get_env_value ENTERPRISE_DB_PASSWORD)"
    if [[ -z "$COMMUNITY_DB_PASSWORD" || -z "$ENTERPRISE_DB_PASSWORD" ]]; then
      echo "The existing .env file is missing a database password. It was not overwritten because existing Docker volumes may still depend on it."
      exit 1
    fi
    COMMUNITY_ADMIN_PASSWORD="$(get_env_value COMMUNITY_ADMIN_PASSWORD)"
    ENTERPRISE_ADMIN_PASSWORD="$(get_env_value ENTERPRISE_ADMIN_PASSWORD)"
    COMMUNITY_ADMIN_PASSWORD="${COMMUNITY_ADMIN_PASSWORD:-$(get_config_value config/community/odoo.conf admin_passwd)}"
    ENTERPRISE_ADMIN_PASSWORD="${ENTERPRISE_ADMIN_PASSWORD:-$(get_config_value config/enterprise/odoo.conf admin_passwd)}"
    COMMUNITY_ADMIN_PASSWORD="${COMMUNITY_ADMIN_PASSWORD:-$(openssl rand -hex 24)}"
    ENTERPRISE_ADMIN_PASSWORD="${ENTERPRISE_ADMIN_PASSWORD:-$(openssl rand -hex 24)}"
    ODOO_IMAGE="$(get_env_value ODOO_IMAGE)"
    POSTGRES_IMAGE="$(get_env_value POSTGRES_IMAGE)"
    ODOO_IMAGE="${ODOO_IMAGE:-odoo:19.0-20260908}"
    POSTGRES_IMAGE="${POSTGRES_IMAGE:-postgres:15.19}"
    SAVED_PGADMIN_IMAGE="$(get_env_value PGADMIN_IMAGE)"
    SAVED_PGADMIN_ENABLED="$(get_env_value PGADMIN_ENABLED)"
    SAVED_PGADMIN_PORT="$(get_env_value PGADMIN_PORT)"
    SAVED_PGADMIN_EMAIL="$(get_env_value PGADMIN_EMAIL)"
    SAVED_PGADMIN_PASSWORD="$(get_env_value PGADMIN_PASSWORD)"
    SAVED_PERFORMANCE_MODE="$(get_env_value PERFORMANCE_MODE)"
    SAVED_COMMUNITY_EXPECTED_USERS="$(get_env_value COMMUNITY_EXPECTED_USERS)"
    SAVED_ENTERPRISE_EXPECTED_USERS="$(get_env_value ENTERPRISE_EXPECTED_USERS)"
    SAVED_COMMUNITY_WORKERS="$(get_env_value COMMUNITY_WORKERS)"
    SAVED_ENTERPRISE_WORKERS="$(get_env_value ENTERPRISE_WORKERS)"
    SAVED_ODOO_MAX_CRON_THREADS="$(get_env_value ODOO_MAX_CRON_THREADS)"
    SAVED_ODOO_LIMIT_MEMORY_SOFT="$(get_env_value ODOO_LIMIT_MEMORY_SOFT)"
    SAVED_ODOO_LIMIT_MEMORY_HARD="$(get_env_value ODOO_LIMIT_MEMORY_HARD)"
    SAVED_CUSTOM_ADDONS_PATH="$(get_env_value COMMUNITY_CUSTOM_ADDONS_PATH)"
    SAVED_CUSTOM_ADDONS_PATH="${SAVED_CUSTOM_ADDONS_PATH:-$(get_env_value ENTERPRISE_CUSTOM_ADDONS_PATH)}"
    PGADMIN_IMAGE="${SAVED_PGADMIN_IMAGE:-$PGADMIN_IMAGE}"
    if [[ "$SAVED_PGADMIN_ENABLED" == "true" ]]; then PGADMIN_ENABLED="true"; fi
    PGADMIN_PORT="${SAVED_PGADMIN_PORT:-$PGADMIN_PORT}"
    PGADMIN_EMAIL="${SAVED_PGADMIN_EMAIL:-$PGADMIN_EMAIL}"
    if [[ "$PGADMIN_VOLUME_EXISTS" == "true" &&
          ( -z "$SAVED_PGADMIN_EMAIL" || -z "$SAVED_PGADMIN_PASSWORD" ) ]]; then
      PGADMIN_CREDENTIALS_MISSING="true"
    fi
    PGADMIN_PASSWORD="${SAVED_PGADMIN_PASSWORD:-$(openssl rand -hex 24)}"
    echo "Existing installation detected; database and Odoo master passwords will be reused."
  else
    COMMUNITY_DB_PASSWORD="$(openssl rand -hex 24)"
    ENTERPRISE_DB_PASSWORD="$(openssl rand -hex 24)"
    COMMUNITY_ADMIN_PASSWORD="$(openssl rand -hex 24)"
    ENTERPRISE_ADMIN_PASSWORD="$(openssl rand -hex 24)"
    PGADMIN_PASSWORD="$(openssl rand -hex 24)"
  fi

  configure_custom_addons_directory "$SAVED_CUSTOM_ADDONS_PATH"
  configure_performance_profile
}
