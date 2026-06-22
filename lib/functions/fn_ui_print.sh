# shellcheck shell=bash

: "${COG_UI_JSON:=false}"
: "${COG_UI_DRY_RUN:=false}"
: "${COG_UI_COLOR_STDOUT:=false}"
: "${COG_UI_COLOR_STDERR:=false}"

cog::fn::ui_is_tty() {
  local fd="${1:-1}"
  [[ -t $fd ]]
}

__cog_ui_resolve_color() {
  local fd="$1"

  if [[ -n ${NO_COLOR:-} ]]; then
    printf '%s\n' "false"
  elif [[ -n ${FORCE_COLOR:-} || -n ${CLICOLOR_FORCE:-} ]]; then
    printf '%s\n' "true"
  elif [[ ${CLICOLOR:-} == "0" ]]; then
    printf '%s\n' "false"
  elif cog::fn::ui_is_tty "$fd"; then
    printf '%s\n' "true"
  else
    printf '%s\n' "false"
  fi
}

cog::fn::ui_init() {
  local ctx_name="$1"
  local config_name="$2"
  local -n __ctx_ref="$ctx_name"
  local -n __config_ref="$config_name"

  COG_UI_JSON="${__config_ref[json]:-${__ctx_ref[json]:-false}}"
  COG_UI_DRY_RUN="${__config_ref[dry_run]:-${__ctx_ref[dry_run]:-false}}"
  COG_UI_COLOR_STDOUT="$(__cog_ui_resolve_color 1)"
  COG_UI_COLOR_STDERR="$(__cog_ui_resolve_color 2)"
}

cog::fn::ui_color_enabled() {
  local stream="${1:-stderr}"

  case "$stream" in
    stdout | 1)
      [[ ${COG_UI_COLOR_STDOUT:-false} == true ]]
      ;;
    stderr | 2)
      [[ ${COG_UI_COLOR_STDERR:-false} == true ]]
      ;;
    *)
      return 1
      ;;
  esac
}

cog::fn::ui_data() {
  printf '%s\n' "$*"
}

cog::fn::ui_dataf() {
  local fmt="$1"
  shift
  # shellcheck disable=SC2059 # Callers pass trusted static format strings.
  printf "$fmt" "$@"
}

cog::fn::ui_human() {
  printf '%s\n' "$*" >&2
}

cog::fn::ui_humanf() {
  local fmt="$1"
  shift
  # shellcheck disable=SC2059 # Callers pass trusted static format strings.
  printf "$fmt" "$@" >&2
}

cog::fn::ui_warn() {
  cog::fn::ui_human "Warning: $*"
}

cog::fn::ui_error_line() {
  cog::fn::ui_human "$*"
}
