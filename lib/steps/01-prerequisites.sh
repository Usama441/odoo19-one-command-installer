#!/usr/bin/env bash
# Sourced by install-ubuntu.sh -- not meant to run standalone.

step_prepare_prerequisites() {
  section "1/6" "Prepare Ubuntu and check requirements"
  echo "Ubuntu package maintenance"
  echo "This updates installed packages only; it does not change the Ubuntu release."
  if ask_yes_no "Refresh package lists and upgrade installed Ubuntu packages now? [y/N]: " "n"; then
    sudo apt-get update
    APT_INDEX_READY="true"
    sudo env DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
    if [[ -f /var/run/reboot-required ]]; then
      echo
      echo "Ubuntu reports that a reboot is required after the package upgrade."
      if ! ask_yes_no "Continue this installation before rebooting? [y/N]: " "n"; then
        echo "Restart Ubuntu, then run this installer again."
        exit 0
      fi
    fi
  else
    echo "Skipping the optional Ubuntu package upgrade."
  fi

  refresh_prerequisite_status
  show_prerequisite_status

  MISSING_COUNT=0
  for installed in "$HAS_CA_CERTIFICATES" "$HAS_CURL" "$HAS_OPENSSL" "$HAS_DOCKER" "$HAS_COMPOSE"; do
    if [[ "$installed" != "true" ]]; then MISSING_COUNT=$((MISSING_COUNT + 1)); fi
  done

  if (( MISSING_COUNT > 0 )); then
    echo
    echo "Missing prerequisites were found."
    echo "  1) Install all missing requirements (recommended)"
    echo "  2) Review and approve each requirement"
    echo "  3) Cancel"
    read_choice PREREQUISITE_MODE "Choose an option [1]: " "1" "1 2 3 a all o one one-by-one q quit cancel"

    INSTALL_CA_CERTIFICATES="false"
    INSTALL_CURL="false"
    INSTALL_OPENSSL="false"
    INSTALL_DOCKER="false"
    INSTALL_COMPOSE="false"

    case "${PREREQUISITE_MODE,,}" in
      1|a|all)
        [[ "$HAS_CA_CERTIFICATES" != "true" ]] && INSTALL_CA_CERTIFICATES="true"
        [[ "$HAS_CURL" != "true" ]] && INSTALL_CURL="true"
        [[ "$HAS_OPENSSL" != "true" ]] && INSTALL_OPENSSL="true"
        [[ "$HAS_DOCKER" != "true" ]] && INSTALL_DOCKER="true"
        [[ "$HAS_COMPOSE" != "true" ]] && INSTALL_COMPOSE="true"
        ;;
      2|o|one|one-by-one)
        if [[ "$HAS_CA_CERTIFICATES" != "true" ]] &&
           ask_yes_no "Install CA certificates? [y/N]: " "n"; then INSTALL_CA_CERTIFICATES="true"; fi
        if [[ "$HAS_CURL" != "true" ]] &&
           ask_yes_no "Install curl? [y/N]: " "n"; then INSTALL_CURL="true"; fi
        if [[ "$HAS_OPENSSL" != "true" ]] &&
           ask_yes_no "Install OpenSSL? [y/N]: " "n"; then INSTALL_OPENSSL="true"; fi
        if [[ "$HAS_DOCKER" != "true" ]] &&
           ask_yes_no "Install Docker Engine (includes required repository packages)? [y/N]: " "n"; then INSTALL_DOCKER="true"; fi
        if [[ "$HAS_COMPOSE" != "true" ]] &&
           ask_yes_no "Install the Docker Compose plugin (includes required repository packages)? [y/N]: " "n"; then INSTALL_COMPOSE="true"; fi
        ;;
      3|q|quit|cancel)
        echo "Installation cancelled; no missing prerequisites were installed."
        exit 0
        ;;
      *)
        echo "Choose 1, 2, or 3."
        exit 1
        ;;
    esac

    if [[ "$INSTALL_DOCKER" == "true" || "$INSTALL_COMPOSE" == "true" ]]; then
      INSTALL_CA_CERTIFICATES="true"
      INSTALL_CURL="true"
    fi

    if [[ "${PREREQUISITE_MODE,,}" == "1" || "${PREREQUISITE_MODE,,}" == "a" || "${PREREQUISITE_MODE,,}" == "all" ]]; then
      SUPPORT_PACKAGES=()
      TRACK_SUPPORT_PACKAGES=()
      [[ "$INSTALL_CA_CERTIFICATES" == "true" ]] && SUPPORT_PACKAGES+=(ca-certificates)
      [[ "$INSTALL_CURL" == "true" ]] && SUPPORT_PACKAGES+=(curl)
      [[ "$INSTALL_OPENSSL" == "true" ]] && SUPPORT_PACKAGES+=(openssl)
      [[ "$INSTALL_CA_CERTIFICATES" == "true" && "$HAS_CA_CERTIFICATES" != "true" ]] && TRACK_SUPPORT_PACKAGES+=(ca-certificates)
      [[ "$INSTALL_CURL" == "true" && "$HAS_CURL" != "true" ]] && TRACK_SUPPORT_PACKAGES+=(curl)
      [[ "$INSTALL_OPENSSL" == "true" && "$HAS_OPENSSL" != "true" ]] && TRACK_SUPPORT_PACKAGES+=(openssl)
      if (( ${#SUPPORT_PACKAGES[@]} > 0 )); then
        install_apt_packages "${SUPPORT_PACKAGES[@]}"
        if (( ${#TRACK_SUPPORT_PACKAGES[@]} > 0 )); then
          track_installer_packages "${TRACK_SUPPORT_PACKAGES[@]}"
        fi
      fi
    else
      if [[ "$INSTALL_CA_CERTIFICATES" == "true" ]]; then
        install_apt_packages ca-certificates
        if [[ "$HAS_CA_CERTIFICATES" != "true" ]]; then
          track_installer_packages ca-certificates
        fi
      fi
      if [[ "$INSTALL_CURL" == "true" ]]; then
        install_apt_packages curl
        if [[ "$HAS_CURL" != "true" ]]; then
          track_installer_packages curl
        fi
      fi
      if [[ "$INSTALL_OPENSSL" == "true" ]]; then
        install_apt_packages openssl
        if [[ "$HAS_OPENSSL" != "true" ]]; then
          track_installer_packages openssl
        fi
      fi
    fi

    if [[ "$INSTALL_DOCKER" == "true" || "$INSTALL_COMPOSE" == "true" ]]; then
      setup_docker_repository
    fi
    if [[ "$INSTALL_DOCKER" == "true" ]]; then
      echo "Installing Docker Engine..."
      install_apt_packages docker-ce docker-ce-cli containerd.io docker-buildx-plugin
      track_installer_packages docker-ce docker-ce-cli containerd.io docker-buildx-plugin
      if package_installed docker-ce-rootless-extras; then
        track_installer_packages docker-ce-rootless-extras
      fi
      if ! id -nG "$USER" | tr ' ' '\n' | grep -Fxq docker; then
        sudo usermod -aG docker "$USER"
        INSTALLER_DOCKER_GROUP_USER="$USER"
        save_installer_state
      fi
    fi
    if [[ "$INSTALL_COMPOSE" == "true" ]]; then
      echo "Installing the Docker Compose plugin..."
      if ! install_apt_packages docker-compose-plugin; then
        echo "Docker Compose could not be installed. Check the Docker repository configuration, then rerun this installer."
        exit 1
      fi
      track_installer_packages docker-compose-plugin
    fi
  fi

  refresh_prerequisite_status
  show_prerequisite_status
  if [[ "$HAS_OPENSSL" != "true" || "$HAS_DOCKER" != "true" || "$HAS_COMPOSE" != "true" ]]; then
    echo "OpenSSL, Docker Engine, and Docker Compose are required. Rerun the installer and approve the missing items."
    exit 1
  fi

  resolve_install_docker_endpoint || exit 1

  if systemctl cat docker.service >/dev/null 2>&1; then
    echo "Enabling Docker to start automatically at boot..."
    if ! sudo systemctl enable --now docker.service; then
      echo "Docker could not be enabled and started. Fix the Docker system service, then rerun this installer."
      exit 1
    fi
  else
    echo "Warning: docker.service was not found, so automatic Docker startup could not be configured."
  fi

  DOCKER=(docker --host "$INSTALL_DOCKER_ENDPOINT")
  if ! "${DOCKER[@]}" info >/dev/null 2>&1; then
    if sudo docker --host "$INSTALL_DOCKER_ENDPOINT" info >/dev/null 2>&1; then
      DOCKER=(sudo docker --host "$INSTALL_DOCKER_ENDPOINT")
    else
      echo "Docker is installed, but its engine is not running. Start Docker and rerun this installer."
      exit 1
    fi
  fi

  verify_install_docker_engine || exit 1

  if ! "${DOCKER[@]}" compose version >/dev/null 2>&1; then
    echo "Docker Compose is unavailable. Rerun the installer and approve the Compose plugin installation."
    exit 1
  fi
  COMPOSE_UP_HELP="$("${DOCKER[@]}" compose up --help 2>&1)"
  if [[ "$COMPOSE_UP_HELP" != *"--wait-timeout"* ]]; then
    echo "This installer requires a newer Docker Compose plugin with --wait support. Update Docker Engine/Compose, then rerun it."
    exit 1
  fi

  if [[ "$INSTALL_ACTION" == "dependencies" ]]; then
    echo
    printf '%b\n' "${COLOR_GREEN}Dependency check complete. Ubuntu is ready for the Odoo installer.${COLOR_RESET}"
    exit 0
  fi
}
