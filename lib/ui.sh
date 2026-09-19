#!/usr/bin/env bash
# Sourced by install-ubuntu.sh -- not meant to run standalone.

print_banner() {
  printf '%b' "$COLOR_PURPLE$COLOR_BOLD"
  cat <<EOF

============================================================
             ODOO 19 DEPLOYMENT CONTROL CENTER
                    Installer v$INSTALLER_VERSION
     Community • Enterprise • PostgreSQL • pgAdmin
                  Script by TI ASSOCIATES
              Developed by USAMA ARSHAD
============================================================
EOF
  printf '%b' "$COLOR_RESET"
}

section() {
  printf '\n%b[%s] %s%b\n' "$COLOR_CYAN$COLOR_BOLD" "$1" "$2" "$COLOR_RESET"
  printf '%s\n' "------------------------------------------------------------"
}

menu_item() {
  printf '  %b[%s]%b %s\n' "$COLOR_GREEN$COLOR_BOLD" "$1" "$COLOR_RESET" "$2"
}

ask_yes_no() {
  local prompt="$1" default_answer="$2" answer
  while true; do
    read -r -p "$prompt" answer
    answer="${answer:-$default_answer}"
    case "${answer,,}" in
      y|yes) return 0 ;;
      n|no) return 1 ;;
      *) echo "Please enter y for yes or n for no." ;;
    esac
  done
}

read_choice() {
  local target="$1" prompt="$2" default_answer="$3" allowed="$4" answer
  while true; do
    read -r -p "$prompt" answer
    answer="${answer:-$default_answer}"
    answer="${answer,,}"
    if [[ " $allowed " == *" $answer "* ]]; then
      printf -v "$target" '%s' "$answer"
      return
    fi
    echo "Please choose one of the listed options."
  done
}

repeat_character() {
  local character="$1" count="$2" repeated
  printf -v repeated '%*s' "$count" ''
  printf '%s' "${repeated// /$character}"
}

print_padded_text() {
  local LC_ALL=C
  local content="$1" width="$2" content_width=0 padding index byte byte_value

  # Bash printf measures %-Ns fields in bytes under some Ubuntu locales.
  # Count UTF-8 leading bytes instead so terminal borders remain aligned.
  for (( index = 0; index < ${#content}; index++ )); do
    byte="${content:index:1}"
    printf -v byte_value '%d' "'$byte"
    if (( (byte_value & 0xC0) != 0x80 )); then
      content_width=$((content_width + 1))
    fi
  done

  printf '%s' "$content"
  if (( content_width < width )); then
    padding=$((width - content_width))
    printf '%*s' "$padding" ''
  fi
}
