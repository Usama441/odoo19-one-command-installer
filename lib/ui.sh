#!/usr/bin/env bash
# Sourced by install-ubuntu.sh -- not meant to run standalone.

print_banner() {
  printf '%b' "$COLOR_PURPLE$COLOR_BOLD"
  cat <<EOF

============================================================
               ODOO DEPLOYMENT CONTROL CENTER
                    Installer v$INSTALLER_VERSION
     Community • Enterprise • PostgreSQL • pgAdmin
                  Script by TI ASSOCIATES
              Developed by USAMA ARSHAD
============================================================
EOF
  printf '%b' "$COLOR_RESET"
}

# "19 & 20" style list of the selectable Odoo major versions.
supported_odoo_versions_label() {
  local version label=""
  for version in "${SUPPORTED_ODOO_VERSIONS[@]}"; do
    label+="${label:+ & }${version%%.*}"
  done
  printf '%s' "$label"
}

section() {
  printf '\n%b[%s] %s%b\n' "$COLOR_CYAN$COLOR_BOLD" "$1" "$2" "$COLOR_RESET"
  printf '%s\n' "------------------------------------------------------------"
}

menu_item() {
  printf '  %b[%s]%b %s\n' "$COLOR_GREEN$COLOR_BOLD" "$1" "$COLOR_RESET" "$2"
}

# Prompts never accept an empty answer, so an accidental Enter cannot pick a
# value. A bracketed default in a prompt ("Port [8069]: ") is shown as a
# suggestion instead ("Port (suggested: 8069): ") and must be typed.
format_prompt() {
  local prompt="$1" pattern='^(.*) \[([^]]*)\](: *)$'
  if [[ ! "$prompt" =~ $pattern ]]; then
    printf '%s' "$prompt"
    return
  fi
  case "${BASH_REMATCH[2]}" in
    Y/n) printf '%s [y/n] (suggested: y)%s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[3]}" ;;
    y/N) printf '%s [y/n] (suggested: n)%s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[3]}" ;;
    *) printf '%s (suggested: %s)%s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}" ;;
  esac
}

# Reads a non-empty answer into the variable named by $1.
read_value() {
  local __rv_target="$1" __rv_prompt="$2" __rv_answer
  while true; do
    if ! read -r -p "$(format_prompt "$__rv_prompt")" __rv_answer && [[ -z "$__rv_answer" ]]; then
      echo
      echo "Input ended before an answer was given; stopping without changes."
      exit 1
    fi
    if [[ -n "${__rv_answer//[[:space:]]/}" ]]; then
      printf -v "$__rv_target" '%s' "$__rv_answer"
      return
    fi
    echo "Nothing was entered. Please type your answer."
  done
}

ask_yes_no() {
  local prompt="$1" answer
  while true; do
    read_value answer "$prompt"
    case "${answer,,}" in
      y|yes) return 0 ;;
      n|no) return 1 ;;
      *) echo "Please enter y for yes or n for no." ;;
    esac
  done
}

# Asks the user to type a confirmation phrase exactly. A mistyped phrase gets up
# to three attempts; pressing Enter on an empty answer cancels immediately.
confirm_phrase() {
  local phrase="$1" prompt="$2" answer attempt max_attempts=3
  for (( attempt = 1; attempt <= max_attempts; attempt++ )); do
    read -r -p "$prompt" answer
    if [[ "$answer" == "$phrase" ]]; then
      return 0
    fi
    if [[ -z "$answer" ]]; then
      return 1
    fi
    if (( attempt < max_attempts )); then
      echo "That does not match \"$phrase\" (capital letters and spaces must match)."
      echo "$((max_attempts - attempt)) attempt(s) left; press Enter to cancel."
    fi
  done
  echo "The phrase did not match after $max_attempts attempts."
  return 1
}

read_choice() {
  local target="$1" prompt="$2" allowed="$4" answer
  while true; do
    read_value answer "$prompt"
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
