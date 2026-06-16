# shellcheck shell=bash
: 'desc: Check cog runtime health and installation prerequisites.'

__cog_doctor_add_check() {
  local checks_name="$1"
  local name="$2"
  local status="$3"
  local detail="${4:-}"
  local path="${5:-}"
  local -n __checks_ref="$checks_name"
  local check_json

  check_json="$(jq -n \
    --arg name "$name" \
    --arg status "$status" \
    --arg detail "$detail" \
    --arg path "$path" \
    '{
      name: $name,
      status: $status
    }
    + (if $detail == "" then {} else {detail: $detail} end)
    + (if $path == "" then {} else {path: $path} end)')"
  __checks_ref+=("$check_json")
}

__cog_doctor_worst_status() {
  local current="$1"
  local next="$2"

  if [[ $current == error || $next == error ]]; then
    cog::fn::ui_data "error"
  elif [[ $current == warn || $next == warn ]]; then
    cog::fn::ui_data "warn"
  else
    cog::fn::ui_data "ok"
  fi
}

__cog_doctor_emit_json() {
  local status="$1"
  local version="$2"
  shift 2
  local json checks_json

  checks_json="$(printf '%s\n' "$@" | jq -s '.')"
  json="$(jq -n \
    --arg schema "cog.doctor.v1" \
    --arg status "$status" \
    --arg version "$version" \
    --argjson checks "$checks_json" \
    '{schema: $schema, status: $status, version: $version, checks: $checks}')"

  cog::fn::json_emit '.schema=="cog.doctor.v1" and (.checks|length>0)' "$json"
}

cog::cmd::doctor() {
  local version_file="${LIB_DIR}/../VERSION"
  local version
  local overall="ok"
  local exit_code=0
  local hard_failure_kind=""
  local dep dep_path status detail
  local -a checks=()
  local -a deps=(bash jq git find sed mktemp)
  local xdg_config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
  local xdg_state_home="${XDG_STATE_HOME:-$HOME/.local/state}"
  local xdg_cache_home="${XDG_CACHE_HOME:-$HOME/.cache}"
  local xdg_data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
  local state_parent="${xdg_state_home%/*}"
  local bin_path="${LIB_DIR}/../bin/cog"
  local module
  local -a eager_modules=(
    "${LIB_DIR}/functions/fn_ui_print.sh"
    "${LIB_DIR}/functions/fn_log.sh"
    "${LIB_DIR}/functions/fn_error_raise.sh"
    "${LIB_DIR}/functions/fn_json_write.sh"
  )

  [[ -r $version_file ]] || cog::fn::error_raise "VersionUnavailable" \
    "VERSION file is missing or unreadable" "path: ${version_file}" "" ""
  version="$(<"$version_file")"

  if ! __have jq; then
    cog::fn::error_raise "MissingRequirement" \
      "required command not found" "command: jq" "" "install jq and retry"
  fi

  __cog_doctor_add_check checks "version" "ok" "$version" "$version_file"

  for dep in "${deps[@]}"; do
    if dep_path="$(command -v "$dep" 2>/dev/null)"; then
      __cog_doctor_add_check checks "dependency:${dep}" "ok" "$dep_path"
    else
      __cog_doctor_add_check checks "dependency:${dep}" "error" "required command not found"
      overall="$(__cog_doctor_worst_status "$overall" error)"
      [[ -n $hard_failure_kind ]] || hard_failure_kind="dependency"
    fi
  done

  __cog_doctor_add_check checks "xdg_config_home" "ok" "" "$xdg_config_home"
  __cog_doctor_add_check checks "xdg_cache_home" "ok" "" "$xdg_cache_home"
  __cog_doctor_add_check checks "xdg_data_home" "ok" "" "$xdg_data_home"

  if [[ -d $state_parent && -w $state_parent ]] || mkdir -p "$xdg_state_home" 2>/dev/null; then
    __cog_doctor_add_check checks "xdg_state_home" "ok" "" "$xdg_state_home"
  else
    __cog_doctor_add_check checks "xdg_state_home" "error" "state home is not creatable or writable" "$xdg_state_home"
    overall="$(__cog_doctor_worst_status "$overall" error)"
    [[ -n $hard_failure_kind ]] || hard_failure_kind="config"
  fi

  if [[ -r $bin_path && -x $bin_path ]]; then
    __cog_doctor_add_check checks "install:bin" "ok" "" "$bin_path"
  else
    __cog_doctor_add_check checks "install:bin" "error" "bin/cog is not readable and executable" "$bin_path"
    overall="$(__cog_doctor_worst_status "$overall" error)"
    [[ -n $hard_failure_kind ]] || hard_failure_kind="config"
  fi

  if [[ -r $LIB_DIR ]]; then
    __cog_doctor_add_check checks "install:lib" "ok" "" "$LIB_DIR"
  else
    __cog_doctor_add_check checks "install:lib" "error" "lib directory is not readable" "$LIB_DIR"
    overall="$(__cog_doctor_worst_status "$overall" error)"
    [[ -n $hard_failure_kind ]] || hard_failure_kind="config"
  fi

  if [[ -r ${LIB_DIR}/commands ]]; then
    __cog_doctor_add_check checks "install:commands" "ok" "" "${LIB_DIR}/commands"
  else
    __cog_doctor_add_check checks "install:commands" "error" "command directory is not readable" "${LIB_DIR}/commands"
    overall="$(__cog_doctor_worst_status "$overall" error)"
    [[ -n $hard_failure_kind ]] || hard_failure_kind="config"
  fi

  for module in "${eager_modules[@]}"; do
    if [[ -r $module ]]; then
      status="ok"
      detail=""
    else
      status="error"
      detail="eager module is not readable"
      overall="$(__cog_doctor_worst_status "$overall" error)"
      [[ -n $hard_failure_kind ]] || hard_failure_kind="config"
    fi
    __cog_doctor_add_check checks "install:module:${module##*/}" "$status" "$detail" "$module"
  done

  case "$hard_failure_kind" in
    dependency)
      exit_code="$EX_UNAVAILABLE"
      ;;
    config)
      exit_code="$EX_CONFIG"
      ;;
    *)
      exit_code=0
      ;;
  esac

  if [[ ${COG_UI_JSON:-false} == true ]]; then
    __cog_doctor_emit_json "$overall" "$version" "${checks[@]}"
  else
    if [[ $overall == ok ]]; then
      cog::fn::ui_data "DOCTOR_OK"
      cog::fn::ui_human "cog doctor: ok"
    else
      cog::fn::ui_data "DOCTOR_FAILED ${hard_failure_kind:-unknown}"
      cog::fn::ui_warn "cog doctor: ${overall}"
    fi
  fi

  return "$exit_code"
}
