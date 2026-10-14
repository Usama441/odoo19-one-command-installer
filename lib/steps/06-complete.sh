#!/usr/bin/env bash
# Sourced by install-ubuntu.sh -- not meant to run standalone.

step_show_completion() {
  section "6/6" "Installation complete"
  cat installation-info.txt
  echo
  echo "Next steps:"
  if [[ "$START_COMMUNITY" == "true" ]]; then
    echo "  - Open the Community URL and use its master password on the database creation page."
  fi
  if [[ "$START_ENTERPRISE" == "true" ]]; then
    echo "  - Open the Enterprise URL and use its master password on the database creation page."
  fi
  if [[ "$PGADMIN_ENABLED" == "true" ]]; then
    echo "  - Sign in to pgAdmin with the email and password shown above."
  fi
  if [[ "$PROXY_ENABLED" == "true" && "$PROXY_CERT_MODE" == "local-ca" ]]; then
    echo "  - On each computer or phone, open $(proxy_ca_page_url) once and install the"
    echo "    company certificate (Windows: one-click installer, run as administrator)."
    echo "    After that the Odoo HTTPS address opens with a normal padlock."
    echo "    Keep $SCRIPT_DIR/$PROXY_CA_DIR backed up: replacing it means reinstalling on every device."
  fi
  echo "Credentials are stored in $SCRIPT_DIR/installation-info.txt (owner-readable only)."
  echo "Place custom modules in $ODOO_HOST_CUSTOM_ADDONS_DIR, then update the Apps list in Odoo."
}
