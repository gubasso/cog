# shellcheck shell=bash

cog::fn::prereq_add_check() {
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

cog::fn::prereq_worst_status() {
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

cog::fn::prereq_xdg_homes() {
  local homes_name="$1"
  local -n __homes_ref="$homes_name"

  # shellcheck disable=SC2154 # Keys index the caller's associative array via __homes_ref nameref.
  __homes_ref=(
    [config_home]="${XDG_CONFIG_HOME:-$HOME/.config}"
    [state_home]="${XDG_STATE_HOME:-$HOME/.local/state}"
    [cache_home]="${XDG_CACHE_HOME:-$HOME/.cache}"
    [data_home]="${XDG_DATA_HOME:-$HOME/.local/share}"
  )
}

cog::fn::prereq_runtime_dirs() {
  local dirs_name="$1"
  local -n __dirs_ref="$dirs_name"
  local -A homes=()

  cog::fn::prereq_xdg_homes homes
  # shellcheck disable=SC2154 # Keys index the caller's associative array via __dirs_ref nameref.
  __dirs_ref=(
    [config]="${homes[config_home]}/cog"
    [state]="${homes[state_home]}/cog"
    [cache]="${homes[cache_home]}/cog"
    [data]="${homes[data_home]}/cog"
  )
}

cog::fn::prereq_collect_checks() {
  local checks_name="$1"
  local overall_name="$2"
  local hard_failure_kind_name="$3"
  # shellcheck disable=SC2178 # Nameref targets the caller's checks array; reset to empty below.
  local -n __checks_ref="$checks_name"
  local -n __overall_ref="$overall_name"
  local -n __hard_failure_kind_ref="$hard_failure_kind_name"
  local version_file="${LIB_DIR}/../VERSION"
  local version
  local dep dep_path status detail
  local -a deps=(bash jq git find sed mktemp)
  local -A homes=()
  local state_parent
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

  __checks_ref=()
  cog::fn::prereq_xdg_homes homes
  state_parent="${homes[state_home]%/*}"

  cog::fn::prereq_add_check "$checks_name" "version" "ok" "$version" "$version_file"

  for dep in "${deps[@]}"; do
    if dep_path="$(command -v "$dep" 2>/dev/null)"; then
      cog::fn::prereq_add_check "$checks_name" "dependency:${dep}" "ok" "$dep_path"
    else
      cog::fn::prereq_add_check "$checks_name" "dependency:${dep}" "error" "required command not found"
      __overall_ref="$(cog::fn::prereq_worst_status "$__overall_ref" error)"
      [[ -n $__hard_failure_kind_ref ]] || __hard_failure_kind_ref="dependency"
    fi
  done

  cog::fn::prereq_add_check "$checks_name" "xdg_config_home" "ok" "" "${homes[config_home]}"
  cog::fn::prereq_add_check "$checks_name" "xdg_cache_home" "ok" "" "${homes[cache_home]}"
  cog::fn::prereq_add_check "$checks_name" "xdg_data_home" "ok" "" "${homes[data_home]}"

  if [[ -d $state_parent && -w $state_parent ]] || mkdir -p "${homes[state_home]}" 2>/dev/null; then
    cog::fn::prereq_add_check "$checks_name" "xdg_state_home" "ok" "" "${homes[state_home]}"
  else
    cog::fn::prereq_add_check "$checks_name" "xdg_state_home" "error" "state home is not creatable or writable" "${homes[state_home]}"
    __overall_ref="$(cog::fn::prereq_worst_status "$__overall_ref" error)"
    [[ -n $__hard_failure_kind_ref ]] || __hard_failure_kind_ref="config"
  fi

  if [[ -r $bin_path && -x $bin_path ]]; then
    cog::fn::prereq_add_check "$checks_name" "install:bin" "ok" "" "$bin_path"
  else
    cog::fn::prereq_add_check "$checks_name" "install:bin" "error" "bin/cog is not readable and executable" "$bin_path"
    __overall_ref="$(cog::fn::prereq_worst_status "$__overall_ref" error)"
    [[ -n $__hard_failure_kind_ref ]] || __hard_failure_kind_ref="config"
  fi

  if [[ -r $LIB_DIR ]]; then
    cog::fn::prereq_add_check "$checks_name" "install:lib" "ok" "" "$LIB_DIR"
  else
    cog::fn::prereq_add_check "$checks_name" "install:lib" "error" "lib directory is not readable" "$LIB_DIR"
    __overall_ref="$(cog::fn::prereq_worst_status "$__overall_ref" error)"
    [[ -n $__hard_failure_kind_ref ]] || __hard_failure_kind_ref="config"
  fi

  if [[ -r ${LIB_DIR}/commands ]]; then
    cog::fn::prereq_add_check "$checks_name" "install:commands" "ok" "" "${LIB_DIR}/commands"
  else
    cog::fn::prereq_add_check "$checks_name" "install:commands" "error" "command directory is not readable" "${LIB_DIR}/commands"
    __overall_ref="$(cog::fn::prereq_worst_status "$__overall_ref" error)"
    [[ -n $__hard_failure_kind_ref ]] || __hard_failure_kind_ref="config"
  fi

  for module in "${eager_modules[@]}"; do
    if [[ -r $module ]]; then
      status="ok"
      detail=""
    else
      status="error"
      detail="eager module is not readable"
      __overall_ref="$(cog::fn::prereq_worst_status "$__overall_ref" error)"
      [[ -n $__hard_failure_kind_ref ]] || __hard_failure_kind_ref="config"
    fi
    cog::fn::prereq_add_check "$checks_name" "install:module:${module##*/}" "$status" "$detail" "$module"
  done
}

cog::fn::prereq_exit_code() {
  local hard_failure_kind="$1"

  case "$hard_failure_kind" in
    dependency)
      cog::fn::ui_data "$EX_UNAVAILABLE"
      ;;
    config)
      cog::fn::ui_data "$EX_CONFIG"
      ;;
    *)
      cog::fn::ui_data 0
      ;;
  esac
}
