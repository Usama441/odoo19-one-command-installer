#!/usr/bin/env bash
# Sourced by install-ubuntu.sh -- not meant to run standalone.

step_configure_pgadmin() {
  section "4/6" "Choose optional pgAdmin"
  echo "pgAdmin is an optional browser-based database manager."
  echo "Odoo works normally without it."
  if [[ "$PGADMIN_ENABLED" == "true" ]]; then
    if ask_yes_no "Keep pgAdmin enabled? [Y/n]: " "y"; then
      PGADMIN_ENABLED="true"
    else
      PGADMIN_ENABLED="false"
    fi
  else
    if ask_yes_no "Add pgAdmin to this installation? [y/N]: " "n"; then
      PGADMIN_ENABLED="true"
    else
      PGADMIN_ENABLED="false"
    fi
  fi

  if [[ "$PGADMIN_ENABLED" == "true" ]]; then
    if [[ "$PGADMIN_CREDENTIALS_MISSING" == "true" ]]; then
      echo "The existing pgAdmin data volume was found, but its saved login credentials are missing from .env. Restore .env from backup before enabling pgAdmin."
      exit 1
    fi
    while true; do
      read -r -p "pgAdmin web port [$PGADMIN_PORT]: " PGADMIN_PORT_INPUT
      PGADMIN_PORT="${PGADMIN_PORT_INPUT:-$PGADMIN_PORT}"
      if ! valid_port "$PGADMIN_PORT"; then
        echo "Please enter a port number from 1 to 65535."
        continue
      fi
      PGADMIN_PORT="$((10#$PGADMIN_PORT))"
      if [[ ( "$START_COMMUNITY" == "true" && "$PGADMIN_PORT" == "$COMMUNITY_PORT" ) ||
            ( "$START_ENTERPRISE" == "true" && "$PGADMIN_PORT" == "$ENTERPRISE_PORT" ) ]]; then
        echo "The pgAdmin port must be different from the enabled Odoo web ports."
        continue
      fi
      break
    done
    if [[ "$PGADMIN_VOLUME_EXISTS" == "true" ]]; then
      echo "Reusing existing pgAdmin login email: $PGADMIN_EMAIL"
    else
      echo "This email is used only to sign in to the local pgAdmin web page."
      while true; do
        read -r -p "pgAdmin login email [$PGADMIN_EMAIL]: " PGADMIN_EMAIL_INPUT
        PGADMIN_EMAIL="${PGADMIN_EMAIL_INPUT:-$PGADMIN_EMAIL}"
        if [[ "$PGADMIN_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then break; fi
        echo "Please enter a valid email address, for example admin@example.com."
      done
    fi
    if [[ ! "$PGADMIN_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
      echo "The saved pgAdmin login email is invalid. Correct PGADMIN_EMAIL in .env, then rerun the installer."
      exit 1
    fi
  fi

  if ! valid_port "$PGADMIN_PORT"; then PGADMIN_PORT="5050"; fi
  if [[ ! "$PGADMIN_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then PGADMIN_EMAIL="admin@example.com"; fi
  if [[ ! "$ODOO_IMAGE" =~ ^[A-Za-z0-9][A-Za-z0-9._/@:-]+$ ||
        ! "$POSTGRES_IMAGE" =~ ^[A-Za-z0-9][A-Za-z0-9._/@:-]+$ ||
        ! "$PGADMIN_IMAGE" =~ ^[A-Za-z0-9][A-Za-z0-9._/@:-]+$ ]]; then
    echo "An image reference in .env is invalid."
    exit 1
  fi
}
