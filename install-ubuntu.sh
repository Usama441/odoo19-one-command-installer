#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER_VERSION="1.1.0"
# Odoo releases offered by the installer, oldest first. Each needs a pinned
# image in odoo_image_for_version (lib/config.sh).
SUPPORTED_ODOO_VERSIONS=(19.0 20.0)
ODOO_VERSION=""
ODOO_MAJOR_VERSION=""
DEFAULT_ODOO_IMAGE=""
ODOO_HOST_ROOT=""
ODOO_HOST_ENTERPRISE_DIR=""
ODOO_HOST_CUSTOM_ROOT=""
ODOO_HOST_CUSTOM_ADDONS_DIR=""
cd "$SCRIPT_DIR"

if [[ -t 0 && -t 1 && "${TERM:-dumb}" != "dumb" ]] &&
   command -v clear >/dev/null 2>&1; then
  clear || true
fi

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  COLOR_PURPLE=$'\033[38;5;97m'
  COLOR_CYAN=$'\033[38;5;37m'
  COLOR_BLUE=$'\033[38;5;81m'
  COLOR_GREEN=$'\033[38;5;34m'
  COLOR_RED=$'\033[38;5;196m'
  COLOR_YELLOW=$'\033[38;5;214m'
  COLOR_WHITE=$'\033[38;5;255m'
  COLOR_MUTED=$'\033[38;5;110m'
  COLOR_MAGENTA_BG=$'\033[48;5;97m'
  COLOR_BOLD=$'\033[1m'
  COLOR_RESET=$'\033[0m'
else
  COLOR_PURPLE=""
  COLOR_CYAN=""
  COLOR_BLUE=""
  COLOR_GREEN=""
  COLOR_RED=""
  COLOR_YELLOW=""
  COLOR_WHITE=""
  COLOR_MUTED=""
  COLOR_MAGENTA_BG=""
  COLOR_BOLD=""
  COLOR_RESET=""
fi

LIB_DIR="$SCRIPT_DIR/lib"
for _installer_lib in ui dashboard system config backup uninstall; do
  # shellcheck source=/dev/null
  source "$LIB_DIR/${_installer_lib}.sh"
done
unset _installer_lib LIB_DIR

# Start from the version of an existing installation so the dashboard,
# backup, and uninstall flows see its paths; installs ask again later.
set_odoo_version "$(detect_installed_odoo_version)"

STEPS_DIR="$SCRIPT_DIR/lib/steps"
for _installer_step in 00-bootstrap 01-prerequisites 02-deployment-mode 03-prepare-edition 04-pgadmin 05-review-and-install 06-complete; do
  # shellcheck source=/dev/null
  source "$STEPS_DIR/${_installer_step}.sh"
done
unset _installer_step STEPS_DIR

main() {
  step_bootstrap_and_menu
  step_prepare_prerequisites
  step_choose_deployment_mode
  step_prepare_edition
  step_configure_pgadmin
  step_review_and_install
  step_show_completion
}

main
