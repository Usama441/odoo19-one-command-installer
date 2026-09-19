#!/usr/bin/env bash
# Sourced by install-ubuntu.sh -- not meant to run standalone.

uninstall_list_contains() {
  local wanted="$1" item
  shift
  for item in "$@"; do
    [[ "$item" == "$wanted" ]] && return 0
  done
  return 1
}

discover_foreign_docker_resources() {
  local resource_name project_label network_name

  UNINSTALL_FOREIGN_DOCKER_RESOURCES=()
  while IFS='|' read -r resource_name project_label; do
    [[ -n "$resource_name" ]] || continue
    if [[ "$project_label" != "odoo19-dual" ]]; then
      UNINSTALL_FOREIGN_DOCKER_RESOURCES+=("container: $resource_name")
    fi
  done < <(
    "${UNINSTALL_DOCKER_COMMAND[@]}" ps -a \
      --format '{{.Names}}|{{.Label "com.docker.compose.project"}}' 2>/dev/null || true
  )

  while IFS='|' read -r resource_name project_label; do
    [[ -n "$resource_name" ]] || continue
    if [[ "$project_label" != "odoo19-dual" ]]; then
      UNINSTALL_FOREIGN_DOCKER_RESOURCES+=("volume: $resource_name")
    fi
  done < <(
    "${UNINSTALL_DOCKER_COMMAND[@]}" volume ls \
      --format '{{.Name}}|{{.Label "com.docker.compose.project"}}' 2>/dev/null || true
  )

  while IFS='|' read -r network_name project_label; do
    [[ -n "$network_name" ]] || continue
    case "$network_name" in
      bridge|host|none) continue ;;
    esac
    if [[ "$project_label" != "odoo19-dual" ]]; then
      UNINSTALL_FOREIGN_DOCKER_RESOURCES+=("network: $network_name")
    fi
  done < <(
    "${UNINSTALL_DOCKER_COMMAND[@]}" network ls \
      --format '{{.Name}}|{{.Label "com.docker.compose.project"}}' 2>/dev/null || true
  )
}

verify_installed_source_targets() {
  local source_path resolved_path

  UNINSTALL_VERIFIED_SOURCE_PATHS=()
  for source_path in "${UNINSTALL_SOURCE_TARGETS[@]}"; do
    [[ -e "$source_path" ]] || continue
    resolved_path="$(realpath -m -- "$source_path")"
    case "$resolved_path" in
      "$ODOO_HOST_ENTERPRISE_DIR"|"$ODOO_HOST_CUSTOM_ROOT")
        UNINSTALL_VERIFIED_SOURCE_PATHS+=("$resolved_path")
        ;;
      *)
        printf '  [SKIP]  %s (outside the installer-managed source boundary)\n' "$source_path"
        ;;
    esac
  done
}

audit_uninstall_targets() {
  local service container_details container_line volume volume_details project_label volume_label mountpoint
  local discovered_volume file_path package networks network_line project_containers source_path protected_path
  local foreign_resource found_protected="false"

  UNINSTALL_VERIFIED_VOLUMES=()
  section "UNINSTALL AUDIT" "Read-only discovery before removal"
  echo "Scope: $UNINSTALL_SCOPE_NAME"
  echo "Safety boundary: Compose project label 'odoo19-dual', installer state, and known generated paths."
  echo
  echo "Containers:"
  for service in "${UNINSTALL_TARGET_SERVICES[@]}"; do
    container_details="$(
      "${UNINSTALL_DOCKER_COMMAND[@]}" ps -a \
        --filter "label=com.docker.compose.project=odoo19-dual" \
        --filter "label=com.docker.compose.service=$service" \
        --format '{{.Names}} | {{.Status}}' 2>/dev/null || true
    )"
    if [[ -n "$container_details" ]]; then
      while IFS= read -r container_line; do
        printf '  [FOUND] %-18s %s\n' "$service" "$container_line"
      done <<< "$container_details"
    else
      printf '  [NONE]  %s\n' "$service"
    fi
  done
  if [[ "$UNINSTALL_SCOPE_NAME" == "complete installer stack" ]]; then
    project_containers="$(
      "${UNINSTALL_DOCKER_COMMAND[@]}" ps -a \
        --filter "label=com.docker.compose.project=odoo19-dual" \
        --format '{{.Names}} | service={{.Label "com.docker.compose.service"}} | {{.Status}}' 2>/dev/null || true
    )"
    echo "  Complete project-label scan (includes possible orphan containers):"
    if [[ -n "$project_containers" ]]; then
      while IFS= read -r container_line; do printf '    [FOUND] %s\n' "$container_line"; done <<< "$project_containers"
    else
      echo "    [NONE]"
    fi
  fi

  if [[ "$UNINSTALL_SCOPE_NAME" == "complete installer stack" ]]; then
    while IFS= read -r discovered_volume; do
      [[ -n "$discovered_volume" ]] || continue
      if ! uninstall_list_contains "$discovered_volume" "${UNINSTALL_TARGET_VOLUMES[@]}"; then
        UNINSTALL_TARGET_VOLUMES+=("$discovered_volume")
      fi
    done < <(
      "${UNINSTALL_DOCKER_COMMAND[@]}" volume ls \
        --filter "label=com.docker.compose.project=odoo19-dual" \
        --format '{{.Name}}' 2>/dev/null || true
    )
  fi

  echo
  echo "Persistent Docker volumes:"
  for volume in "${UNINSTALL_TARGET_VOLUMES[@]}"; do
    volume_details="$(
      "${UNINSTALL_DOCKER_COMMAND[@]}" volume inspect \
        --format '{{ index .Labels "com.docker.compose.project" }}|{{ index .Labels "com.docker.compose.volume" }}|{{ .Mountpoint }}' \
        "$volume" 2>/dev/null || true
    )"
    if [[ -z "$volume_details" ]]; then
      printf '  [NONE]  %s\n' "$volume"
      continue
    fi
    IFS='|' read -r project_label volume_label mountpoint <<< "$volume_details"
    if [[ "$project_label" != "odoo19-dual" ]]; then
      printf '  [SKIP]  %s (project ownership label does not match)\n' "$volume"
      continue
    fi
    if [[ "$UNINSTALL_SCOPE_NAME" != "complete installer stack" &&
          "$volume_label" != "${volume#odoo19-dual_}" ]]; then
      printf '  [SKIP]  %s (volume ownership label does not match)\n' "$volume"
      continue
    fi
    UNINSTALL_VERIFIED_VOLUMES+=("$volume")
    printf '  [FOUND] %s\n' "$volume"
    printf '          mount: %s\n' "${mountpoint:-managed by Docker}"
  done

  echo
  echo "Generated host files:"
  for file_path in "${UNINSTALL_GENERATED_FILES[@]}"; do
    if [[ -d "$file_path" && ! -L "$file_path" ]]; then
      printf '  [FOUND DIRECTORY PLACEHOLDER] %s\n' "$file_path"
    elif [[ -e "$file_path" ]]; then
      printf '  [FOUND] %s\n' "$file_path"
    else
      printf '  [NONE]  %s\n' "$file_path"
    fi
  done
  if [[ "$UNINSTALL_SCOPE_NAME" != "complete installer stack" ]]; then
    printf '  [KEEP]  %s and %s (shared by remaining services)\n' \
      "$SCRIPT_DIR/.env" "$SCRIPT_DIR/installation-info.txt"
  fi

  if [[ "$UNINSTALL_SCOPE_NAME" == "complete installer stack" ]]; then
    networks="$(
      "${UNINSTALL_DOCKER_COMMAND[@]}" network ls \
        --filter "label=com.docker.compose.project=odoo19-dual" \
        --format '{{.Name}}' 2>/dev/null || true
    )"
    echo
    echo "Project networks:"
    if [[ -n "$networks" ]]; then
      while IFS= read -r network_line; do printf '  [FOUND] %s\n' "$network_line"; done <<< "$networks"
    else
      echo "  [NONE]"
    fi

    echo
    echo "Installer-tracked system setup:"
    if (( ${#INSTALLER_MANAGED_PACKAGES[@]} > 0 )); then
      for package in "${INSTALLER_MANAGED_PACKAGES[@]}"; do
        if package_installed "$package"; then
          printf '  [FOUND] package %s\n' "$package"
        else
          printf '  [NONE]  package %s\n' "$package"
        fi
      done
    else
      echo "  [REVIEW] no installer-owned package record; older Docker installs need separate confirmation"
    fi
    if [[ "$INSTALLER_CREATED_DOCKER_SOURCE" == "true" ]]; then
      if [[ -e /etc/apt/sources.list.d/docker.list ]]; then
        echo "  [FOUND] /etc/apt/sources.list.d/docker.list (installer-created)"
      else
        echo "  [NONE]  tracked Docker APT source is already absent"
      fi
    fi
    if [[ "$INSTALLER_CREATED_DOCKER_KEY" == "true" ]]; then
      if [[ -e /etc/apt/keyrings/docker.asc ]]; then
        echo "  [FOUND] /etc/apt/keyrings/docker.asc (installer-created)"
      else
        echo "  [NONE]  tracked Docker APT signing key is already absent"
      fi
    fi
    if [[ -n "$INSTALLER_DOCKER_GROUP_USER" ]]; then
      printf '  [FOUND] tracked Docker group access for %s\n' "$INSTALLER_DOCKER_GROUP_USER"
    fi

    discover_foreign_docker_resources
    echo
    echo "Docker resources outside this Odoo installer:"
    if (( ${#UNINSTALL_FOREIGN_DOCKER_RESOURCES[@]} > 0 )); then
      for foreign_resource in "${UNINSTALL_FOREIGN_DOCKER_RESOURCES[@]}"; do
        printf '  [KEEP]  %s\n' "$foreign_resource"
      done
      echo "  Docker Engine removal will be blocked to protect these resources."
    else
      echo "  [NONE]  no non-Odoo containers, volumes, or custom networks were found"
    fi
  fi

  echo
  echo "Installed source/addon copies eligible for optional cleanup:"
  verify_installed_source_targets
  if (( ${#UNINSTALL_VERIFIED_SOURCE_PATHS[@]} > 0 )); then
    for source_path in "${UNINSTALL_VERIFIED_SOURCE_PATHS[@]}"; do
      printf '  [FOUND] %s\n' "$source_path"
    done
  else
    echo "  [NONE]"
  fi

  echo
  echo "Original checkout source paths (always preserved):"
  for protected_path in \
    "$SCRIPT_DIR/enterprise-19.0" \
    "$SCRIPT_DIR/addons/enterprise" \
    "$SCRIPT_DIR/addons/community" \
    "$SCRIPT_DIR/addons/enterprise-custom"; do
    if [[ -e "$protected_path" ]]; then
      printf '  [KEEP]  %s\n' "$protected_path"
      found_protected="true"
    fi
  done
  [[ "$found_protected" == "true" ]] || echo "  [NONE]"
  echo
  echo "Anything outside this verified inventory is not a deletion target."
}

remove_installer_managed_dependencies() {
  local package confirmation docker_source_path has_tracked_state="false" remove_detected_docker="false"
  local docker_package_was_tracked="false"
  local detected_docker_key="false"
  local installed_packages=() detected_docker_packages=() detected_docker_source_paths=()

  # Container removal also deletes attached anonymous volumes. Refresh the
  # inventory so removed placeholders do not block confirmed Engine cleanup.
  discover_foreign_docker_resources

  for package in \
    docker-ce docker-ce-cli docker-ce-rootless-extras containerd.io \
    docker-buildx-plugin docker-compose-plugin; do
    if package_installed "$package"; then
      detected_docker_packages+=("$package")
    fi
  done
  for docker_source_path in \
    /etc/apt/sources.list.d/docker.list \
    /etc/apt/sources.list.d/docker.sources; do
    if [[ -f "$docker_source_path" ]] &&
       grep -Fqs 'download.docker.com/linux/ubuntu' "$docker_source_path"; then
      detected_docker_source_paths+=("$docker_source_path")
    fi
  done
  if (( ${#detected_docker_source_paths[@]} > 0 )) &&
     [[ -e /etc/apt/keyrings/docker.asc ]]; then
    detected_docker_key="true"
  fi

  if (( ${#INSTALLER_MANAGED_PACKAGES[@]} > 0 )) ||
     [[ "$INSTALLER_CREATED_DOCKER_SOURCE" == "true" ||
        "$INSTALLER_CREATED_DOCKER_KEY" == "true" ||
        -n "$INSTALLER_DOCKER_GROUP_USER" ]]; then
    has_tracked_state="true"
  fi

  echo
  printf '%b\n' "${COLOR_YELLOW}Dependency cleanup can affect other Docker-based applications.${COLOR_RESET}"
  if [[ "$has_tracked_state" == "true" ]]; then
    echo "Packages recorded as installed by this installer:"
    if (( ${#INSTALLER_MANAGED_PACKAGES[@]} > 0 )); then
      for package in "${INSTALLER_MANAGED_PACKAGES[@]}"; do
        printf '  - %s\n' "$package"
        case "$package" in
          docker-ce|docker-ce-cli|docker-ce-rootless-extras|containerd.io|docker-buildx-plugin|docker-compose-plugin)
            docker_package_was_tracked="true"
            ;;
        esac
      done
    else
      echo "  - no packages"
    fi
  else
    echo "No installer ownership record was found (for example, this may be an older installation)."
    if (( ${#detected_docker_packages[@]} == 0 )) &&
       (( ${#detected_docker_source_paths[@]} == 0 )) &&
       [[ "$detected_docker_key" != "true" ]]; then
      echo "No removable Docker Engine packages or official repository files were detected."
      return 0
    fi
    if (( ${#detected_docker_packages[@]} > 0 )); then
      echo "Detected Docker Engine packages:"
      for package in "${detected_docker_packages[@]}"; do
        printf '  - %s\n' "$package"
      done
    fi
    for docker_source_path in "${detected_docker_source_paths[@]}"; do
      printf '  - detected official Docker APT source: %s\n' "$docker_source_path"
    done
    [[ "$detected_docker_key" == "true" ]] && echo "  - detected official Docker APT signing key"
  fi
  [[ "$INSTALLER_CREATED_DOCKER_SOURCE" == "true" ]] && echo "  - Docker APT source created by this installer"
  [[ "$INSTALLER_CREATED_DOCKER_KEY" == "true" ]] && echo "  - Docker APT signing key created by this installer"
  if [[ -n "$INSTALLER_DOCKER_GROUP_USER" ]]; then
    printf '  - Docker group access added for %s\n' "$INSTALLER_DOCKER_GROUP_USER"
  fi
  if (( ${#UNINSTALL_FOREIGN_DOCKER_RESOURCES[@]} > 0 )) &&
     { (( ${#detected_docker_packages[@]} > 0 )) ||
       [[ "$INSTALLER_CREATED_DOCKER_SOURCE" == "true" ||
          "$INSTALLER_CREATED_DOCKER_KEY" == "true" ||
          -n "$INSTALLER_DOCKER_GROUP_USER" ]]; }; then
    echo
    echo "Docker Engine will NOT be removed because non-Odoo Docker resources were found:"
    for package in "${UNINSTALL_FOREIGN_DOCKER_RESOURCES[@]}"; do
      printf '  - %s\n' "$package"
    done
    echo "Remove or migrate those workloads first, then rerun complete uninstall."
    echo "No Docker packages, repository files, or group access were changed."
    return 0
  elif [[ "$has_tracked_state" == "false" ]]; then
    echo "Ownership cannot be proven, but no non-Odoo Docker resources were detected."
    read -r -p "Type REMOVE DETECTED DOCKER to remove the listed Docker components: " confirmation
    if [[ "$confirmation" == "REMOVE DETECTED DOCKER" ]]; then
      remove_detected_docker="true"
    else
      echo "Detected Docker components were preserved."
      return 0
    fi
  else
    echo "Only installer-recorded items will be removed; untracked software is preserved."
    read -r -p "Type REMOVE DEPENDENCIES to continue: " confirmation
    if [[ "$confirmation" != "REMOVE DEPENDENCIES" ]]; then
      echo "Docker and dependency cleanup skipped."
      return 0
    fi
    if [[ "$docker_package_was_tracked" != "true" ]] &&
       (( ${#detected_docker_packages[@]} > 0 )); then
      echo
      echo "The Docker Engine packages were detected but are not present in the ownership record."
      echo "This can happen when an older installer created Docker before package tracking was added."
      read -r -p "Type REMOVE DETECTED DOCKER to remove those Docker packages too: " confirmation
      if [[ "$confirmation" == "REMOVE DETECTED DOCKER" ]]; then
        remove_detected_docker="true"
      else
        echo "Untracked Docker Engine packages will be preserved."
      fi
    fi
  fi

  if [[ -n "$INSTALLER_DOCKER_GROUP_USER" ]] && getent group docker >/dev/null 2>&1; then
    sudo gpasswd -d "$INSTALLER_DOCKER_GROUP_USER" docker >/dev/null 2>&1 || true
  fi

  for package in "${INSTALLER_MANAGED_PACKAGES[@]}"; do
    if package_installed "$package"; then
      case "$package" in
        docker-ce|docker-ce-cli|docker-ce-rootless-extras|containerd.io|docker-buildx-plugin|docker-compose-plugin)
          if (( ${#UNINSTALL_FOREIGN_DOCKER_RESOURCES[@]} == 0 )); then
            installed_packages+=("$package")
          fi
          ;;
        *) installed_packages+=("$package") ;;
      esac
    fi
  done
  if [[ "$remove_detected_docker" == "true" ||
        ( "$docker_package_was_tracked" == "true" && ${#UNINSTALL_FOREIGN_DOCKER_RESOURCES[@]} -eq 0 ) ]]; then
    for package in "${detected_docker_packages[@]}"; do
      if ! uninstall_list_contains "$package" "${installed_packages[@]}"; then
        installed_packages+=("$package")
      fi
    done
  fi
  if (( ${#installed_packages[@]} > 0 )); then
    sudo env DEBIAN_FRONTEND=noninteractive apt-get purge -y "${installed_packages[@]}"
  fi
  if [[ "$INSTALLER_CREATED_DOCKER_SOURCE" == "true" ]]; then
    sudo rm -f /etc/apt/sources.list.d/docker.list
  fi
  if [[ "$remove_detected_docker" == "true" ]]; then
    for docker_source_path in "${detected_docker_source_paths[@]}"; do
      sudo rm -f -- "$docker_source_path"
    done
  fi
  if [[ "$INSTALLER_CREATED_DOCKER_KEY" == "true" ||
        ( "$remove_detected_docker" == "true" && "$detected_docker_key" == "true" ) ]]; then
    sudo rm -f /etc/apt/keyrings/docker.asc
  fi

  INSTALLER_MANAGED_PACKAGES=()
  INSTALLER_CREATED_DOCKER_SOURCE="false"
  INSTALLER_CREATED_DOCKER_KEY="false"
  INSTALLER_DOCKER_GROUP_USER=""
  rm -f "$INSTALLER_STATE_FILE"
  printf '%b\n' "${COLOR_GREEN}Approved Docker components and installer-tracked dependencies were removed.${COLOR_RESET}"
}

remove_verified_installed_sources() {
  local source_path

  for source_path in "${UNINSTALL_VERIFIED_SOURCE_PATHS[@]}"; do
    case "$source_path" in
      "$ODOO_HOST_ENTERPRISE_DIR"|"$ODOO_HOST_CUSTOM_ROOT")
        sudo rm -rf -- "$source_path"
        ;;
      *)
        printf 'Skipping unverified source path: %s\n' "$source_path"
        ;;
    esac
  done
  sudo rmdir "$ODOO_HOST_ROOT" 2>/dev/null || true
  sudo rmdir "$(dirname -- "$ODOO_HOST_ROOT")" 2>/dev/null || true
}

offer_backup_before_database_deletion() {
  local backup_choice backup_result_file completed_backup_path

  UNINSTALL_DATABASE_DELETE_APPROVED="false"
  while true; do
    echo
    echo "Before deleting databases and filestores:"
    echo "  1) Scan databases, select one or more, and create a RAR backup (recommended)"
    echo "  2) Continue without a backup"
    echo "  3) Cancel database deletion"
    read_choice backup_choice "Choose a backup option [1]: " "1" "1 2 3 backup skip cancel"
    case "${backup_choice,,}" in
      1|backup)
        backup_result_file="$(mktemp /tmp/odoo19-uninstall-backup.XXXXXX)"
        run_backup_manager "$backup_result_file"
        load_installer_state
        if [[ -s "$backup_result_file" ]]; then
          IFS= read -r completed_backup_path < "$backup_result_file"
          if [[ "$completed_backup_path" == "$SCRIPT_DIR/backups/system-databases-"*.rar &&
                -s "$completed_backup_path" ]]; then
            rm -f -- "$backup_result_file"
            echo
            printf '%b\n' "${COLOR_GREEN}Pre-uninstall database backup completed.${COLOR_RESET}"
            printf 'Verified archive: %s\n' "$completed_backup_path"
            UNINSTALL_DATABASE_DELETE_APPROVED="true"
            return 0
          fi
        fi
        rm -f -- "$backup_result_file"
        echo "No backup archive was created. Database deletion has not been approved."
        ;;
      2|skip)
        printf '%b\n' "${COLOR_YELLOW}WARNING: Continuing without a backup can cause permanent data loss.${COLOR_RESET}"
        if ask_yes_no "Continue to the permanent-delete confirmation without a backup? [y/N]: " "n"; then
          UNINSTALL_DATABASE_DELETE_APPROVED="true"
          return 0
        fi
        ;;
      3|cancel)
        echo "Database deletion cancelled. Nothing has been removed."
        return 0
        ;;
    esac
  done
}

force_remove_uninstall_containers() {
  local service container_id project_label service_label
  local removal_failed="false"
  local -a container_ids=() remaining_ids=()

  if [[ "$UNINSTALL_SCOPE_NAME" == "complete installer stack" ]]; then
    mapfile -t container_ids < <(
      "${UNINSTALL_DOCKER_COMMAND[@]}" ps -aq \
        --filter "label=com.docker.compose.project=odoo19-dual"
    )
  else
    for service in "${UNINSTALL_TARGET_SERVICES[@]}"; do
      while IFS= read -r container_id; do
        [[ -n "$container_id" ]] || continue
        if ! uninstall_list_contains "$container_id" "${container_ids[@]}"; then
          container_ids+=("$container_id")
        fi
      done < <(
        "${UNINSTALL_DOCKER_COMMAND[@]}" ps -aq \
          --filter "label=com.docker.compose.project=odoo19-dual" \
          --filter "label=com.docker.compose.service=$service"
      )
    done
  fi

  for container_id in "${container_ids[@]}"; do
    project_label="$(
      "${UNINSTALL_DOCKER_COMMAND[@]}" inspect \
        --format '{{ index .Config.Labels "com.docker.compose.project" }}' \
        "$container_id" 2>/dev/null || true
    )"
    service_label="$(
      "${UNINSTALL_DOCKER_COMMAND[@]}" inspect \
        --format '{{ index .Config.Labels "com.docker.compose.service" }}' \
        "$container_id" 2>/dev/null || true
    )"
    if [[ "$project_label" != "odoo19-dual" ]]; then
      echo "Refusing to remove container $container_id because its project label changed."
      removal_failed="true"
      continue
    fi
    if [[ "$UNINSTALL_SCOPE_NAME" != "complete installer stack" ]] &&
       ! uninstall_list_contains "$service_label" "${UNINSTALL_TARGET_SERVICES[@]}"; then
      echo "Refusing to remove container $container_id because its service label changed."
      removal_failed="true"
      continue
    fi
    if ! "${UNINSTALL_DOCKER_COMMAND[@]}" stop --time 90 "$container_id" >/dev/null 2>&1; then
      echo "Container $container_id did not stop gracefully; forcing its removal."
    fi
    # -v removes anonymous volumes attached to this verified container. Named
    # database/filestore volumes remain controlled by the separate data choice.
    if ! "${UNINSTALL_DOCKER_COMMAND[@]}" rm -f -v "$container_id"; then
      echo "Failed to forcibly remove installer container $container_id."
      removal_failed="true"
    fi
  done

  if [[ "$UNINSTALL_SCOPE_NAME" == "complete installer stack" ]]; then
    mapfile -t remaining_ids < <(
      "${UNINSTALL_DOCKER_COMMAND[@]}" ps -aq \
        --filter "label=com.docker.compose.project=odoo19-dual"
    )
  else
    for service in "${UNINSTALL_TARGET_SERVICES[@]}"; do
      while IFS= read -r container_id; do
        [[ -n "$container_id" ]] && remaining_ids+=("$container_id")
      done < <(
        "${UNINSTALL_DOCKER_COMMAND[@]}" ps -aq \
          --filter "label=com.docker.compose.project=odoo19-dual" \
          --filter "label=com.docker.compose.service=$service"
      )
    done
  fi
  if (( ${#remaining_ids[@]} > 0 )); then
    echo "The following selected containers still exist:"
    printf '  - %s\n' "${remaining_ids[@]}"
    removal_failed="true"
  fi

  [[ "$removal_failed" == "false" ]]
}

force_remove_complete_project_networks() {
  local network_name project_label removal_failed="false"
  local -a network_names=() remaining_networks=()

  mapfile -t network_names < <(
    "${UNINSTALL_DOCKER_COMMAND[@]}" network ls \
      --filter "label=com.docker.compose.project=odoo19-dual" \
      --format '{{.Name}}'
  )
  for network_name in "${network_names[@]}"; do
    project_label="$(
      "${UNINSTALL_DOCKER_COMMAND[@]}" network inspect \
        --format '{{ index .Labels "com.docker.compose.project" }}' \
        "$network_name" 2>/dev/null || true
    )"
    if [[ "$project_label" != "odoo19-dual" ]]; then
      echo "Refusing to remove network $network_name because its project label changed."
      removal_failed="true"
      continue
    fi
    if ! "${UNINSTALL_DOCKER_COMMAND[@]}" network rm "$network_name"; then
      echo "Failed to remove installer network $network_name."
      removal_failed="true"
    fi
  done

  mapfile -t remaining_networks < <(
    "${UNINSTALL_DOCKER_COMMAND[@]}" network ls \
      --filter "label=com.docker.compose.project=odoo19-dual" \
      --format '{{.Name}}'
  )
  if (( ${#remaining_networks[@]} > 0 )); then
    echo "The following installer networks still exist:"
    printf '  - %s\n' "${remaining_networks[@]}"
    removal_failed="true"
  fi

  [[ "$removal_failed" == "false" ]]
}

remove_verified_uninstall_volumes() {
  local volume volume_details project_label volume_label removal_failed="false"
  local -a remaining_volumes=()

  for volume in "${UNINSTALL_VERIFIED_VOLUMES[@]}"; do
    volume_details="$(
      "${UNINSTALL_DOCKER_COMMAND[@]}" volume inspect \
        --format '{{ index .Labels "com.docker.compose.project" }}|{{ index .Labels "com.docker.compose.volume" }}' \
        "$volume" 2>/dev/null || true
    )"
    [[ -n "$volume_details" ]] || continue
    IFS='|' read -r project_label volume_label <<< "$volume_details"
    if [[ "$project_label" != "odoo19-dual" ]]; then
      echo "Refusing to remove volume $volume because its project label changed."
      removal_failed="true"
      continue
    fi
    if [[ "$UNINSTALL_SCOPE_NAME" != "complete installer stack" &&
          "$volume_label" != "${volume#odoo19-dual_}" ]]; then
      echo "Refusing to remove volume $volume because its ownership label changed."
      removal_failed="true"
      continue
    fi
    if ! "${UNINSTALL_DOCKER_COMMAND[@]}" volume rm -f "$volume"; then
      echo "Failed to forcibly remove installer volume $volume."
      removal_failed="true"
    fi
  done

  for volume in "${UNINSTALL_VERIFIED_VOLUMES[@]}"; do
    if "${UNINSTALL_DOCKER_COMMAND[@]}" volume inspect "$volume" >/dev/null 2>&1; then
      remaining_volumes+=("$volume")
    fi
  done
  if (( ${#remaining_volumes[@]} > 0 )); then
    echo "The following selected volumes still exist:"
    printf '  - %s\n' "${remaining_volumes[@]}"
    removal_failed="true"
  fi

  [[ "$removal_failed" == "false" ]]
}

remove_verified_generated_files() {
  local file_path removal_failed="false"

  for file_path in "${UNINSTALL_GENERATED_FILES[@]}"; do
    if [[ -d "$file_path" && ! -L "$file_path" ]]; then
      # Docker creates an empty directory at a missing bind-mounted file path.
      # Never recurse through unexpected content at a generated-file path.
      if ! rmdir -- "$file_path"; then
        echo "Refusing to recursively remove non-empty directory placeholder $file_path."
        removal_failed="true"
      fi
    elif ! rm -f -- "$file_path"; then
      echo "Failed to remove generated file $file_path."
      removal_failed="true"
    fi
  done
  for file_path in "${UNINSTALL_GENERATED_FILES[@]}"; do
    if [[ -e "$file_path" ]]; then
      echo "Failed to remove generated file $file_path."
      removal_failed="true"
    fi
  done

  [[ "$removal_failed" == "false" ]]
}

run_uninstaller() {
  section "UNINSTALL" "Choose exactly what should be removed"
  echo "The audit runs first. Data, installed addon copies, and Docker require separate confirmations."

  if ! command -v docker >/dev/null 2>&1; then
    echo "Docker CLI is unavailable, so existing containers and volumes cannot be audited."
    echo "No local credentials or configuration were removed. Reinstall/start native Docker Engine,"
    echo "then rerun complete uninstall so Docker resources can be verified before local cleanup."
    return 1
  fi

  if ! resolve_install_docker_endpoint; then
    echo "Uninstall stopped before changing anything because the native Docker endpoint could not be verified."
    return 1
  fi

  local docker_command=(docker --host "$INSTALL_DOCKER_ENDPOINT")
  if ! "${docker_command[@]}" info >/dev/null 2>&1; then
    if sudo docker --host "$INSTALL_DOCKER_ENDPOINT" info >/dev/null 2>&1; then
      docker_command=(sudo docker --host "$INSTALL_DOCKER_ENDPOINT")
    else
      echo "Docker is installed, but its engine is not currently available."
      if systemctl cat docker.service >/dev/null 2>&1 &&
         ask_yes_no "Start Docker temporarily so its resources can be audited and removed? [Y/n]: " "y"; then
        sudo systemctl start docker.service
      fi
      if docker --host "$INSTALL_DOCKER_ENDPOINT" info >/dev/null 2>&1; then
        docker_command=(docker --host "$INSTALL_DOCKER_ENDPOINT")
      elif sudo docker --host "$INSTALL_DOCKER_ENDPOINT" info >/dev/null 2>&1; then
        docker_command=(sudo docker --host "$INSTALL_DOCKER_ENDPOINT")
      else
        echo "Docker could not be started. Nothing was removed because its containers and volumes could not be audited safely."
        return
      fi
    fi
  fi
  local engine_identity
  engine_identity="$("${docker_command[@]}" info --format '{{.OSType}}|{{.OperatingSystem}}|{{.Name}}')"
  if [[ "$engine_identity" != linux\|* || "${engine_identity,,}" == *'docker desktop'* ||
        "${engine_identity,,}" == *'docker-desktop'* ]]; then
    echo "Uninstall requires the native Linux Docker Engine that owns this installer's resources."
    echo "Nothing was removed. Select the local Engine context and rerun complete uninstall."
    return 1
  fi
  echo
  echo "Current installer-managed containers:"
  "${docker_command[@]}" ps -a \
    --filter "label=com.docker.compose.project=odoo19-dual" \
    --format 'table {{.Names}}\t{{.Status}}'
  echo
  echo "What do you want to uninstall?"
  echo "  1) Community only"
  echo "  2) Enterprise only"
  echo "  3) Both Odoo editions (keep pgAdmin)"
  echo "  4) Complete stack + optional installed files and Docker cleanup"
  echo "  5) Cancel"

  local uninstall_scope data_choice source_choice confirmation confirmation_text
  local remove_dependencies="false" remove_installed_sources="false"
  local services=() volumes=() generated_files=()
  read_choice uninstall_scope "Choose an uninstall scope [5]: " "5" "1 2 3 4 5 community enterprise both all cancel"
  case "${uninstall_scope,,}" in
    1|community)
      services=(community db-community)
      volumes=(odoo19-dual_community-db odoo19-dual_community-data)
      generated_files=("$SCRIPT_DIR/config/community/odoo.conf")
      UNINSTALL_SCOPE_NAME="Community only"
      confirmation_text="DELETE COMMUNITY"
      UNINSTALL_SOURCE_TARGETS=()
      ;;
    2|enterprise)
      services=(enterprise db-enterprise)
      volumes=(odoo19-dual_enterprise-db odoo19-dual_enterprise-data)
      generated_files=("$SCRIPT_DIR/config/enterprise/odoo.conf")
      UNINSTALL_SCOPE_NAME="Enterprise only"
      confirmation_text="DELETE ENTERPRISE"
      UNINSTALL_SOURCE_TARGETS=("$ODOO_HOST_ENTERPRISE_DIR")
      ;;
    3|both)
      services=(community db-community enterprise db-enterprise)
      volumes=(odoo19-dual_community-db odoo19-dual_community-data odoo19-dual_enterprise-db odoo19-dual_enterprise-data)
      generated_files=("$SCRIPT_DIR/config/community/odoo.conf" "$SCRIPT_DIR/config/enterprise/odoo.conf")
      UNINSTALL_SCOPE_NAME="both Odoo editions; pgAdmin preserved"
      confirmation_text="DELETE BOTH"
      UNINSTALL_SOURCE_TARGETS=("$ODOO_HOST_ENTERPRISE_DIR" "$ODOO_HOST_CUSTOM_ROOT")
      ;;
    4|all)
      services=(community db-community enterprise db-enterprise pgadmin)
      volumes=(odoo19-dual_community-db odoo19-dual_community-data odoo19-dual_enterprise-db odoo19-dual_enterprise-data odoo19-dual_pgadmin-data)
      generated_files=(
        "$SCRIPT_DIR/.env"
        "$SCRIPT_DIR/installation-info.txt"
        "$SCRIPT_DIR/config/community/odoo.conf"
        "$SCRIPT_DIR/config/enterprise/odoo.conf"
        "$SCRIPT_DIR/config/pgadmin/servers.json"
        "$SCRIPT_DIR/config/pgadmin/pgpass"
      )
      UNINSTALL_SCOPE_NAME="complete installer stack"
      confirmation_text="DELETE ALL"
      remove_dependencies="true"
      UNINSTALL_SOURCE_TARGETS=("$ODOO_HOST_ENTERPRISE_DIR" "$ODOO_HOST_CUSTOM_ROOT")
      ;;
    5|cancel)
      echo "Uninstall cancelled; nothing was removed."
      return
      ;;
  esac

  UNINSTALL_DOCKER_COMMAND=("${docker_command[@]}")
  UNINSTALL_TARGET_SERVICES=("${services[@]}")
  UNINSTALL_TARGET_VOLUMES=("${volumes[@]}")
  UNINSTALL_GENERATED_FILES=("${generated_files[@]}")
  audit_uninstall_targets

  echo
  echo "What should happen to the selected databases and filestores?"
  echo "  1) Keep databases and filestores; remove only selected containers (recommended)"
  echo "  2) Back up optionally, then permanently delete selected databases and filestores"
  echo "  3) Cancel"
  read_choice data_choice "Choose a data option [1]: " "1" "1 2 3 keep delete cancel"
  case "${data_choice,,}" in
    1|keep) data_choice="keep" ;;
    2|delete)
      printf '%b\n' "${COLOR_YELLOW}WARNING: Selected database and filestore volumes will be permanently deleted.${COLOR_RESET}"
      offer_backup_before_database_deletion
      if [[ "$UNINSTALL_DATABASE_DELETE_APPROVED" != "true" ]]; then
        echo "Uninstall cancelled; nothing was removed."
        return
      fi
      read -r -p "Type $confirmation_text to confirm: " confirmation
      if [[ "$confirmation" != "$confirmation_text" ]]; then
        echo "Permanent uninstall cancelled; nothing was removed."
        return
      fi
      data_choice="delete"
      ;;
    3|cancel)
      echo "Uninstall cancelled; nothing was removed."
      return
      ;;
  esac

  if (( ${#UNINSTALL_VERIFIED_SOURCE_PATHS[@]} > 0 )); then
    echo
    echo "What should happen to the installed source/addon copies listed in the audit?"
    echo "  1) Keep installed copies under $ODOO_HOST_ROOT (recommended)"
    echo "  2) Permanently delete the listed installed copies"
    echo "  3) Cancel"
    echo "Your original licensed source inside this Git checkout will not be deleted."
    read_choice source_choice "Choose a source option [1]: " "1" "1 2 3 keep delete cancel"
    case "${source_choice,,}" in
      1|keep) ;;
      2|delete)
        printf '%b\n' "${COLOR_YELLOW}WARNING: Every file in the listed /opt folders will be permanently deleted.${COLOR_RESET}"
        read -r -p "Type DELETE INSTALLED SOURCE to confirm: " confirmation
        if [[ "$confirmation" != "DELETE INSTALLED SOURCE" ]]; then
          echo "Permanent source cleanup cancelled; nothing was removed."
          return
        fi
        remove_installed_sources="true"
        ;;
      3|cancel)
        echo "Uninstall cancelled; nothing was removed."
        return
        ;;
    esac
  fi

  if ! ask_yes_no "Proceed with this verified uninstall plan? [y/N]: " "n"; then
    echo "Uninstall cancelled; nothing was removed."
    return
  fi

  echo "Stopping and forcibly removing the verified installer containers..."
  if ! force_remove_uninstall_containers; then
    echo "Uninstall stopped. Generated files were preserved because container removal was incomplete."
    return 1
  fi
  if [[ "${uninstall_scope,,}" == "4" || "${uninstall_scope,,}" == "all" ]]; then
    if ! force_remove_complete_project_networks; then
      echo "Uninstall stopped. Generated files were preserved because network removal was incomplete."
      return 1
    fi
  fi
  if [[ "$data_choice" == "delete" ]]; then
    if ! remove_verified_uninstall_volumes; then
      echo "Uninstall stopped. Generated files were preserved because volume removal was incomplete."
      return 1
    fi
    if ! remove_verified_generated_files; then
      echo "Uninstall stopped because generated-file cleanup was incomplete."
      return 1
    fi
  fi
  if [[ "$remove_installed_sources" == "true" ]]; then
    remove_verified_installed_sources
  fi

  echo
  if [[ "$data_choice" == "delete" ]]; then
    printf '%b\n' "${COLOR_GREEN}Verified selected containers, volumes, and generated files were removed.${COLOR_RESET}"
  else
    printf '%b\n' "${COLOR_GREEN}Selected containers were removed; databases, filestores, and generated files were preserved.${COLOR_RESET}"
  fi
  if (( ${#UNINSTALL_VERIFIED_SOURCE_PATHS[@]} > 0 )); then
    if [[ "$remove_installed_sources" == "true" ]]; then
      printf '%b\n' "${COLOR_GREEN}Verified installed source/addon copies under /opt were removed.${COLOR_RESET}"
    else
      echo "Installed Enterprise/custom-addon copies under /opt were preserved."
    fi
  fi

  if [[ "$remove_dependencies" == "true" ]]; then
    echo
    if ask_yes_no "Also remove Docker and dependencies installed by this installer? [y/N]: " "n"; then
      remove_installer_managed_dependencies
    else
      echo "Docker and Ubuntu dependencies were preserved."
    fi
  fi
  echo "Original source folders in this Git checkout were preserved."
}
