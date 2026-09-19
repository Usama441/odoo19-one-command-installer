#!/usr/bin/env bash
# Sourced by install-ubuntu.sh -- not meant to run standalone.

show_control_center_status() {
  local docker_status enterprise_status installation_status
  if command -v docker >/dev/null 2>&1; then
    docker_status="Available"
  else
    docker_status="Not installed"
  fi
  if [[ -f "$SCRIPT_DIR/enterprise-19.0/web_enterprise/__manifest__.py" ||
        -f "$SCRIPT_DIR/enterprise/web_enterprise/__manifest__.py" ||
        -f "$SCRIPT_DIR/addons/enterprise/web_enterprise/__manifest__.py" ||
        -f "$ODOO_HOST_ENTERPRISE_DIR/web_enterprise/__manifest__.py" ]]; then
    enterprise_status="Ready"
  else
    enterprise_status="Not detected"
  fi
  if [[ -f "$SCRIPT_DIR/.env" ]]; then
    installation_status="Existing configuration found"
  else
    installation_status="New installation"
  fi

  echo
  printf '%b\n' "${COLOR_BOLD}Quick system snapshot${COLOR_RESET}"
  printf '  %-22s %s\n' "Ubuntu" "${PRETTY_NAME:-Unknown}"
  printf '  %-22s %s\n' "Hardware" "$SYSTEM_SPEC_SUMMARY"
  printf '  %-22s %s\n' "Docker CLI only" "$docker_status"
  if command -v dockerd >/dev/null 2>&1; then
    printf '  %-22s %s\n' "Local Docker Engine" "Installed (runtime checked during setup)"
  else
    printf '  %-22s %s\n' "Local Docker Engine" "Missing"
  fi
  printf '  %-22s %s\n' "Enterprise addons" "$enterprise_status"
  printf '  %-22s %s\n' "Installer state" "$installation_status"
  echo
  echo "Choose an action below. Press Enter for the recommended default."
}

dashboard_indent() {
  printf '%*s' "$DASHBOARD_LEFT" ''
}

dashboard_centered_text() {
  local color="$1" content="$2" content_width left_padding
  content_width="${#content}"
  left_padding=$(((DASHBOARD_WIDTH - content_width) / 2))
  (( left_padding < 0 )) && left_padding=0
  printf '%*s%b%s%b\n' "$((DASHBOARD_LEFT + left_padding))" '' "$color" "$content" "$COLOR_RESET"
}

dashboard_border() {
  dashboard_indent
  printf '%b%s' "$COLOR_PURPLE" "$1"
  repeat_character '─' "$((DASHBOARD_WIDTH - 2))"
  printf '%s%b\n' "$2" "$COLOR_RESET"
}

dashboard_line() {
  local color="$1" content="$2"
  dashboard_indent
  printf '│  %b' "$color"
  print_padded_text "$content" "$DASHBOARD_CONTENT_WIDTH"
  printf '%b  │\n' "$COLOR_RESET"
}

dashboard_header_row() {
  local left_color="$1" left="$2" center_color="$3" center="$4" right_color="$5" right="$6"
  local center_width=$((DASHBOARD_CONTENT_WIDTH - 51))
  dashboard_indent
  printf '%b│%b  %b' "$COLOR_PURPLE" "$COLOR_RESET" "$left_color"
  print_padded_text "$left" 18
  printf '%b %b│%b %b' "$COLOR_RESET" "$COLOR_MUTED" "$COLOR_RESET" "$center_color"
  print_padded_text "$center" "$center_width"
  printf '%b %b│%b %b' "$COLOR_RESET" "$COLOR_MUTED" "$COLOR_RESET" "$right_color"
  print_padded_text "$right" 27
  printf '%b  %b│%b\n' "$COLOR_RESET" "$COLOR_PURPLE" "$COLOR_RESET"
}

dashboard_snapshot_row() {
  local icon="$1" label="$2" value="$3" value_color="$4"
  local value_width=$((DASHBOARD_CONTENT_WIDTH - 34))
  dashboard_indent
  printf '│  %b' "$COLOR_BLUE$COLOR_BOLD"
  print_padded_text "$icon" 4
  printf '%b' "$COLOR_WHITE"
  print_padded_text "$label" 30
  printf '%b' "$value_color"
  print_padded_text "$value" "$value_width"
  printf '%b  │\n' "$COLOR_RESET"
}

draw_interactive_dashboard() {
  local selected="$1" recommended="$2"
  local docker_status enterprise_status installation_status

  if command -v docker >/dev/null 2>&1; then
    if command -v dockerd >/dev/null 2>&1; then
      docker_status="●  CLI + Engine installed"
    else
      docker_status="●  CLI only; Engine missing"
    fi
  else
    docker_status="●  Not installed"
  fi
  if enterprise_addons_ready; then
    enterprise_status="●  Ready"
  else
    enterprise_status="●  Not detected"
  fi
  if [[ -f "$SCRIPT_DIR/.env" ]]; then
    installation_status="●  Existing configuration found"
  else
    installation_status="●  New installation"
  fi

  dashboard_border '╭' '╮'
  dashboard_header_row \
    "$COLOR_PURPLE$COLOR_BOLD" "odoo 19" \
    "$COLOR_WHITE$COLOR_BOLD" "ODOO 19 DEPLOYMENT CONTROL CENTER  •  v$INSTALLER_VERSION" \
    "$COLOR_GREEN$COLOR_BOLD" "      ✓  READY"
  dashboard_header_row \
    "$COLOR_PURPLE$COLOR_BOLD" "" \
    "$COLOR_BLUE" "Community  •  Enterprise  •  PostgreSQL  •  pgAdmin" \
    "$COLOR_MUTED" "Script by TI ASSOCIATES"
  dashboard_header_row \
    "$COLOR_PURPLE$COLOR_BOLD" "" \
    "$COLOR_BLUE" "" \
    "$COLOR_MUTED" "Developed by USAMA ARSHAD"
  dashboard_border '╰' '╯'
  echo
  dashboard_centered_text "$COLOR_WHITE$COLOR_BOLD" "Welcome to your all-in-one Odoo 19 deployment workspace."
  dashboard_centered_text "$COLOR_MUTED" "Install, inspect, maintain, or safely remove your stack from one place."
  echo
  dashboard_border '╭' '╮'
  dashboard_line "$COLOR_CYAN$COLOR_BOLD" "▣  SYSTEM SNAPSHOT  ─────────────────────────────────────────────────────────────────────────────────"
  dashboard_snapshot_row "⚙" "Ubuntu" "${PRETTY_NAME:-Unknown}" "$COLOR_WHITE"
  dashboard_snapshot_row "◫" "Hardware" "$SYSTEM_SPEC_SUMMARY" "$COLOR_WHITE"
  if [[ "$docker_status" == *'CLI + Engine installed' ]]; then
    dashboard_snapshot_row "▦" "Local Docker installation" "$docker_status" "$COLOR_GREEN"
  else
    dashboard_snapshot_row "▦" "Local Docker installation" "$docker_status" "$COLOR_YELLOW"
  fi
  if [[ "$enterprise_status" == *Ready ]]; then
    dashboard_snapshot_row "◇" "Enterprise addons" "$enterprise_status" "$COLOR_GREEN"
  else
    dashboard_snapshot_row "◇" "Enterprise addons" "$enterprise_status" "$COLOR_YELLOW"
  fi
  dashboard_snapshot_row "▤" "Installer state" "$installation_status" "$COLOR_GREEN"
  dashboard_border '╰' '╯'
  echo
  dashboard_border '╭' '╮'
  dashboard_line "$COLOR_PURPLE$COLOR_BOLD" "☷  SELECT AN ACTION                         Use ↑/↓ to move  •  Enter to select  •  ★ Recommended"

  draw_interactive_menu_rows "$selected" "$recommended"
  dashboard_border '╰' '╯'
  echo
  dashboard_border '╭' '╮'
  dashboard_line "$COLOR_MUTED" "Enter  Select        ↑↓  Navigate        Esc  Exit        Ctrl+C  Exit"
  dashboard_border '╰' '╯'
}

draw_interactive_menu_rows() {
  local selected="$1" recommended="$2"
  local index label icon tag row_color selector line label_width

  label_width=$((DASHBOARD_CONTENT_WIDTH - 36))

  for index in 1 2 3 4 5 6 7; do
    case "$index" in
      1) icon="⇩"; label="Install Odoo Community only" ;;
      2) icon="⇩"; label="Install Odoo Enterprise only" ;;
      3) icon="⇩"; label="Install both Community and Enterprise" ;;
      4) icon="⚙"; label="Check Ubuntu updates and missing dependencies" ;;
      5) icon="⇧"; label="Back up databases across this system" ;;
      6) icon="♲"; label="Uninstall Odoo" ;;
      7) icon="↩"; label="Exit" ;;
    esac
    tag=""
    if (( index == recommended )); then tag="★ RECOMMENDED"; fi
    selector=" "
    row_color="$COLOR_WHITE"
    if (( index == selected )); then
      selector="›"
      row_color="$COLOR_MAGENTA_BG$COLOR_WHITE$COLOR_BOLD"
    fi
    printf -v line '%s  [%s]  %-3s %-*s %s' "$selector" "$index" "$icon" "$label_width" "$label" "$tag"
    dashboard_line "$row_color" "$line"
  done
}

interactive_terminal_supported() {
  [[ -t 0 && -t 1 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != "dumb" ]] || return 1
  command -v tput >/dev/null 2>&1 || return 1
  tput clear >/dev/null 2>&1 || return 1
  tput cup 0 0 >/dev/null 2>&1 || return 1
  tput civis >/dev/null 2>&1 || return 1
  tput cnorm >/dev/null 2>&1 || return 1
  tput smcup >/dev/null 2>&1 || return 1
  tput rmcup >/dev/null 2>&1 || return 1
}

read_terminal_dimensions() {
  TERMINAL_COLUMNS="$(tput cols 2>/dev/null || printf '0')"
  TERMINAL_ROWS="$(tput lines 2>/dev/null || printf '0')"
  [[ "$TERMINAL_COLUMNS" =~ ^[0-9]+$ && "$TERMINAL_ROWS" =~ ^[0-9]+$ ]] || return 1
  (( TERMINAL_COLUMNS > 0 && TERMINAL_ROWS > 0 ))
}

configure_dashboard_geometry() {
  local viewport_height
  read_terminal_dimensions || return 1
  (( TERMINAL_COLUMNS >= DASHBOARD_MIN_WIDTH && TERMINAL_ROWS >= DASHBOARD_MIN_HEIGHT )) || return 1

  DASHBOARD_WIDTH="$TERMINAL_COLUMNS"
  (( DASHBOARD_WIDTH > DASHBOARD_MAX_WIDTH )) && DASHBOARD_WIDTH="$DASHBOARD_MAX_WIDTH"
  DASHBOARD_CONTENT_WIDTH=$((DASHBOARD_WIDTH - 6))
  DASHBOARD_LEFT=$(((TERMINAL_COLUMNS - DASHBOARD_WIDTH) / 2))

  viewport_height="$TERMINAL_ROWS"
  (( viewport_height > DASHBOARD_MAX_HEIGHT )) && viewport_height="$DASHBOARD_MAX_HEIGHT"
  DASHBOARD_TOP=$(((TERMINAL_ROWS - viewport_height) / 2 + (viewport_height - DASHBOARD_CONTENT_HEIGHT) / 2))
  DASHBOARD_MENU_ROW=$((DASHBOARD_TOP + 20))
}

resize_screen_center_text() {
  local row="$1" color="$2" content="$3" column
  column=$(((TERMINAL_COLUMNS - ${#content}) / 2))
  (( column < 0 )) && column=0
  tput cup "$row" "$column"
  printf '%b%s%b' "$color" "$content" "$COLOR_RESET"
}

draw_resize_window() {
  local box_left=1 box_top=1 box_width box_bottom row title fill_count center_row hint
  box_width=$((TERMINAL_COLUMNS - 2))
  box_bottom=$((TERMINAL_ROWS - 2))
  title='[ resize window ]'
  hint='Resize terminal  |  Q/Esc exit'

  tput clear
  if (( TERMINAL_COLUMNS < 20 || TERMINAL_ROWS < 6 )); then
    tput cup 0 0
    printf '%bNeed %sx%s%b' "$COLOR_RED$COLOR_BOLD" "$DASHBOARD_MIN_WIDTH" "$DASHBOARD_MIN_HEIGHT" "$COLOR_RESET"
    return
  fi
  if (( TERMINAL_COLUMNS < 40 || TERMINAL_ROWS < 12 )); then
    resize_screen_center_text 1 "$COLOR_RED$COLOR_BOLD" "TERMINAL TOO SMALL"
    resize_screen_center_text 3 "$COLOR_WHITE" "Current: ${TERMINAL_COLUMNS}x${TERMINAL_ROWS}"
    resize_screen_center_text 4 "$COLOR_GREEN" "Required: ${DASHBOARD_MIN_WIDTH}x${DASHBOARD_MIN_HEIGHT}"
    return
  fi

  tput cup "$box_top" "$box_left"
  printf '%b┌─%s' "$COLOR_RED" "$title"
  fill_count=$((box_width - ${#title} - 3))
  (( fill_count > 0 )) && repeat_character '─' "$fill_count"
  printf '┐%b' "$COLOR_RESET"

  for (( row = box_top + 1; row < box_bottom; row++ )); do
    tput cup "$row" "$box_left"
    printf '%b│%b' "$COLOR_RED" "$COLOR_RESET"
    tput cup "$row" "$((box_left + box_width - 1))"
    printf '%b│%b' "$COLOR_RED" "$COLOR_RESET"
  done

  tput cup "$box_bottom" "$box_left"
  printf '%b└' "$COLOR_RED"
  repeat_character '─' "$((box_width - 2))"
  printf '┘%b' "$COLOR_RESET"

  center_row=$((TERMINAL_ROWS / 2 - 2))
  resize_screen_center_text "$center_row" "$COLOR_WHITE$COLOR_BOLD" "Current size:"
  resize_screen_center_text "$((center_row + 1))" "$COLOR_RED$COLOR_BOLD" "${TERMINAL_COLUMNS}x${TERMINAL_ROWS}"
  resize_screen_center_text "$((center_row + 3))" "$COLOR_WHITE$COLOR_BOLD" "Need to be at least:"
  resize_screen_center_text "$((center_row + 4))" "$COLOR_GREEN$COLOR_BOLD" "${DASHBOARD_MIN_WIDTH}x${DASHBOARD_MIN_HEIGHT}"
  resize_screen_center_text "$((box_bottom - 1))" "$COLOR_MUTED" "$hint"
}

enable_interactive_input_mode() {
  if [[ -t 0 && -z "$INTERACTIVE_STTY_STATE" ]]; then
    INTERACTIVE_STTY_STATE="$(stty -g 2>/dev/null || true)"
    if [[ -n "$INTERACTIVE_STTY_STATE" ]]; then
      # Keep echo disabled for the whole dashboard session. A touchpad can send
      # several arrow sequences between individual `read -s` calls otherwise.
      stty -echo -icanon min 1 time 0 2>/dev/null || true
    fi
  fi
}

read_dashboard_escape_sequence() {
  local target="$1" first="" character="" escape_data="" index

  IFS= read -rsn1 -t 0.08 first || true
  case "$first" in
    '[')
      escape_data='['
      while (( ${#escape_data} < 32 )); do
        character=""
        IFS= read -rsn1 -t 0.02 character || true
        [[ -n "$character" ]] || break
        escape_data+="$character"
        if [[ "$character" =~ [@-~] ]]; then
          break
        fi
      done
      # Legacy X10 mouse reports contain three coordinate bytes after CSI M.
      if [[ "$escape_data" == '[M' ]]; then
        for index in 1 2 3; do
          character=""
          IFS= read -rsn1 -t 0.02 character || true
          [[ -n "$character" ]] || break
          escape_data+="$character"
        done
      fi
      ;;
    'O')
      character=""
      IFS= read -rsn1 -t 0.02 character || true
      escape_data="O$character"
      ;;
    *) escape_data="$first" ;;
  esac

  printf -v "$target" '%s' "$escape_data"
}

close_interactive_dashboard() {
  printf '%b' "$COLOR_RESET"
  if [[ -n "$INTERACTIVE_STTY_STATE" ]]; then
    stty "$INTERACTIVE_STTY_STATE" 2>/dev/null || true
    INTERACTIVE_STTY_STATE=""
  fi
  tput cnorm 2>/dev/null || printf '\033[?25h'
  if [[ "$INTERACTIVE_ALT_SCREEN" == "true" ]]; then
    tput rmcup 2>/dev/null || true
    INTERACTIVE_ALT_SCREEN="false"
  fi
}

wait_for_dashboard_size() {
  local key sequence last_columns=-1 last_rows=-1

  tput smcup
  INTERACTIVE_ALT_SCREEN="true"
  tput civis
  enable_interactive_input_mode
  trap 'close_interactive_dashboard' EXIT
  trap 'exit 130' INT TERM HUP

  while true; do
    if configure_dashboard_geometry; then
      # Keep the input mode active while handing control to the main menu so a
      # still-running touchpad gesture cannot leak bytes during the transition.
      trap - EXIT INT TERM HUP
      return 0
    fi

    read_terminal_dimensions || {
      close_interactive_dashboard
      trap - EXIT INT TERM HUP
      return 1
    }
    if (( TERMINAL_COLUMNS != last_columns || TERMINAL_ROWS != last_rows )); then
      draw_resize_window
      last_columns="$TERMINAL_COLUMNS"
      last_rows="$TERMINAL_ROWS"
    fi

    key=""
    IFS= read -rsn1 -t 0.25 key || true
    case "$key" in
      q|Q)
        close_interactive_dashboard
        trap - EXIT INT TERM HUP
        return 1
        ;;
      $'\033')
        sequence=""
        read_dashboard_escape_sequence sequence
        if [[ -z "$sequence" ]]; then
          close_interactive_dashboard
          trap - EXIT INT TERM HUP
          return 1
        fi
        ;;
    esac
  done
}

read_interactive_main_choice() {
  local selected="$1" recommended="$1" previous_selected key sequence

  if [[ "$INTERACTIVE_ALT_SCREEN" != "true" ]]; then
    tput smcup
    INTERACTIVE_ALT_SCREEN="true"
  fi
  tput civis
  enable_interactive_input_mode
  trap 'close_interactive_dashboard' EXIT
  trap 'exit 130' INT TERM HUP

  tput clear
  tput cup "$DASHBOARD_TOP" 0
  draw_interactive_dashboard "$selected" "$recommended"

  while true; do
    previous_selected="$selected"
    IFS= read -rsn1 key || true
    case "$key" in
      '') MAIN_CHOICE="$selected"; break ;;
      [1-7]) MAIN_CHOICE="$key"; break ;;
      k|K) (( selected > 1 )) && selected=$((selected - 1)) ;;
      j|J) (( selected < 7 )) && selected=$((selected + 1)) ;;
      q|Q) MAIN_CHOICE="7"; break ;;
      $'\033')
        sequence=""
        read_dashboard_escape_sequence sequence
        case "$sequence" in
          '[A'|'OA') (( selected > 1 )) && selected=$((selected - 1)) ;;
          '[B'|'OB') (( selected < 7 )) && selected=$((selected + 1)) ;;
          '') MAIN_CHOICE="7"; break ;;
        esac
        ;;
    esac

    if (( selected != previous_selected )); then
      # Update only the option rows at their adaptive screen position.
      tput cup "$DASHBOARD_MENU_ROW" 0
      draw_interactive_menu_rows "$selected" "$recommended"
    fi
  done

  close_interactive_dashboard
  trap - EXIT INT TERM HUP
}
