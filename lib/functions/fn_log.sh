# shellcheck shell=bash

: "${COG_LOG_LEVEL_NUM:=2}"
: "${COG_LOG_FILE:=}"
: "${__COG_LOG_WARNED_WRITE_FAILURE:=false}"

cog::fn::log_path() {
  printf '%s\n' "${XDG_STATE_HOME:-$HOME/.local/state}/cog/cog.log"
}

__cog_log_level_num() {
  case "${1:-warn}" in
    error)
      printf '%s\n' 1
      ;;
    warn)
      printf '%s\n' 2
      ;;
    info)
      printf '%s\n' 3
      ;;
    debug)
      printf '%s\n' 4
      ;;
    trace)
      printf '%s\n' 5
      ;;
    *)
      printf '%s\n' 2
      ;;
  esac
}

cog::fn::log_init() {
  local ctx_name="$1"
  local config_name="$2"
  local -n __ctx_ref="$ctx_name"
  local -n __config_ref="$config_name"
  local threshold="${__config_ref[log_level]:-${__ctx_ref[log_level]:-warn}}"

  COG_LOG_LEVEL_NUM="$(__cog_log_level_num "$threshold")"
  COG_LOG_FILE="$(cog::fn::log_path)"
}

cog::fn::log_enabled_for() {
  local level="$1"
  local level_num

  level_num="$(__cog_log_level_num "$level")"
  ((level_num <= ${COG_LOG_LEVEL_NUM:-2}))
}

__cog_log_quote_value() {
  local value="$1"

  if [[ $value =~ [[:space:]=\"] ]]; then
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\r'/\\r}"
    value="${value//$'\t'/\\t}"
    printf '"%s"' "$value"
  else
    printf '%s' "$value"
  fi
}

__cog_log_field() {
  local field="$1"
  local key value

  if [[ $field == *=* ]]; then
    key="${field%%=*}"
    value="${field#*=}"
    printf '%s=' "$key"
    __cog_log_quote_value "$value"
  else
    printf '%s=true' "$field"
  fi
}

__cog_log_warn_write_failure() {
  [[ ${__COG_LOG_WARNED_WRITE_FAILURE:-false} == true ]] && return 0
  __COG_LOG_WARNED_WRITE_FAILURE=true

  if declare -F cog::fn::ui_warn >/dev/null; then
    cog::fn::ui_warn "could not write program log"
  else
    printf '%s\n' "Warning: could not write program log" >&2
  fi
}

cog::fn::log_write() {
  local level="$1"
  local target="$2"
  shift 2

  cog::fn::log_enabled_for "$level" || return 0

  local log_file="${COG_LOG_FILE:-$(cog::fn::log_path)}"
  local log_dir="${log_file%/*}"
  local ts line field rendered

  ts="$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)"
  line="ts=${ts} level=${level} target="
  line+="$(__cog_log_quote_value "$target")"

  for field in "$@"; do
    rendered="$(__cog_log_field "$field")"
    line+=" ${rendered}"
  done

  if ! mkdir -p "$log_dir" 2>/dev/null; then
    __cog_log_warn_write_failure
    return 0
  fi

  if ! printf '%s\n' "$line" 2>/dev/null >>"$log_file"; then
    __cog_log_warn_write_failure
  fi
}

cog::fn::log_error() {
  cog::fn::log_write error "$@"
}

cog::fn::log_warn() {
  cog::fn::log_write warn "$@"
}

cog::fn::log_info() {
  cog::fn::log_write info "$@"
}

cog::fn::log_debug() {
  cog::fn::log_write debug "$@"
}

cog::fn::log_trace() {
  cog::fn::log_write trace "$@"
}
