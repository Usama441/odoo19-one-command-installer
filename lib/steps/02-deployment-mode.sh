#!/usr/bin/env bash
# Sourced by install-ubuntu.sh -- not meant to run standalone.

step_choose_deployment_mode() {
  section "2/6" "Choose how Odoo should run"
  echo "Select a setup profile:"
  echo "  1) Testing (recommended for evaluation and development)"
  echo "  2) Production (opens the hardware-aware performance advisor)"
  read_choice DEPLOYMENT_CHOICE "Choose a profile [1]: " "1" "1 2 testing production"
  case "${DEPLOYMENT_CHOICE,,}" in
    1|testing)
      DEPLOYMENT_MODE="testing"
      BIND_ADDRESS="127.0.0.1"
      ACCESS_HOST="localhost"
      ;;
    2|production)
      DEPLOYMENT_MODE="production"
      BIND_ADDRESS="0.0.0.0"
      ACCESS_HOST=""
      ;;
    *) echo "Choose 1 for testing or 2 for production."; exit 1 ;;
  esac

  echo
  COMMUNITY_PORT="8069"
  ENTERPRISE_PORT="8070"
  if [[ "$START_COMMUNITY" == "true" ]]; then
    echo "The Community web port is used in the browser URL."
    while true; do
      read -r -p "Community web port [8069]: " COMMUNITY_PORT
      COMMUNITY_PORT="${COMMUNITY_PORT:-8069}"
      if valid_port "$COMMUNITY_PORT"; then break; fi
      echo "Please enter a port number from 1 to 65535."
    done
    COMMUNITY_PORT="$((10#$COMMUNITY_PORT))"
  else
    echo "Community was not selected, so its port question is skipped."
  fi

  COMMUNITY_DB_VOLUME_EXISTS="false"
  ENTERPRISE_DB_VOLUME_EXISTS="false"
  PGADMIN_VOLUME_EXISTS="false"
  if "${DOCKER[@]}" volume inspect odoo19-dual_community-db >/dev/null 2>&1; then COMMUNITY_DB_VOLUME_EXISTS="true"; fi
  if "${DOCKER[@]}" volume inspect odoo19-dual_enterprise-db >/dev/null 2>&1; then ENTERPRISE_DB_VOLUME_EXISTS="true"; fi
  if "${DOCKER[@]}" volume inspect odoo19-dual_pgadmin-data >/dev/null 2>&1; then PGADMIN_VOLUME_EXISTS="true"; fi
  if [[ ! -f .env &&
        ( "$COMMUNITY_DB_VOLUME_EXISTS" == "true" || "$ENTERPRISE_DB_VOLUME_EXISTS" == "true" || "$PGADMIN_VOLUME_EXISTS" == "true" ) ]]; then
    echo "Existing installer data volumes were found, but .env is missing. Restore .env from backup; generated replacement credentials would not unlock the existing data."
    exit 1
  fi

  mkdir -p config/community config/enterprise config/pgadmin addons/community addons/enterprise addons/enterprise-custom
}
