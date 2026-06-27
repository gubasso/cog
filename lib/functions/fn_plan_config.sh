# shellcheck shell=bash
# SC2004: array subscripts like arr[$k] do not need ${} on the index; the style
# rule is noise for the integer/string keys used throughout this scanner.
# shellcheck disable=SC2004

__cog_plan_config_allowed_key() {
  case "$1" in
    COG_PLAN_HOME | COG_PLAN_ROOT | COG_PLAN_STORE | COG_PLAN_LOCAL_DIR | COG_PLAN_TRUST | COG_PLAN_CEILING | COG_PLAN_PROJECT | COG_PROJECT_ROOT)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

__cog_plan_config_unquote() {
  local -n __out_ref="$1"
  local token="$2"
  if [[ ${#token} -ge 2 && ${token:0:1} == '"' && ${token: -1} == '"' ]]; then
    __out_ref="${token:1:${#token}-2}"
  elif [[ ${#token} -ge 2 && ${token:0:1} == "'" && ${token: -1} == "'" ]]; then
    __out_ref="${token:1:${#token}-2}"
  else
    __out_ref="$token"
  fi
}

__cog_plan_config_scan_file() {
  local -n __values_ref="$1"
  local -n __file_lines_ref="$2"
  local file="$3"
  local lineno=0 line raw_key value
  local key_re='(COG_PLAN_HOME|COG_PLAN_ROOT|COG_PLAN_STORE|COG_PLAN_LOCAL_DIR|COG_PLAN_TRUST|COG_PLAN_CEILING|COG_PLAN_PROJECT|COG_PROJECT_ROOT|[A-Za-z_][A-Za-z0-9_]*)'
  local val_re='("[^"$`\\]*"|'\''[^'\'']*'\''|[A-Za-z0-9_.:/+-]+)'
  local assign_re="^[[:space:]]*${key_re}[[:space:]]*=[[:space:]]*${val_re}[[:space:]]*$"

  __values_ref=()
  __file_lines_ref=()

  [[ -r $file ]] || return 0
  while IFS= read -r line || [[ -n $line ]]; do
    lineno=$((lineno + 1))
    [[ $line =~ ^[[:space:]]*$ ]] && continue
    [[ $line =~ ^[[:space:]]*# ]] && continue
    [[ $line =~ ^[[:space:]]*:\ \'desc:\ .+\'[[:space:]]*$ ]] && continue

    if [[ ! $line =~ $assign_re ]]; then
      cog::fn::error_raise "InvalidConfigStatement" \
        "plan config line is not a single literal assignment" "where: ${file}:${lineno}" \
        "plan config files may only assign COG_PLAN_* keys to literal values" \
        "use a plain literal assignment; cog config files are not shell scripts"
    fi

    raw_key="${BASH_REMATCH[1]}"
    if ! __cog_plan_config_allowed_key "$raw_key"; then
      cog::fn::error_raise "UnknownConfigKey" \
        "unknown plan config key" "where: ${file}:${lineno} key=${raw_key}" \
        "only COG_PLAN_* plan keys are valid in the plan scanner" "remove or correct the key"
    fi

    __cog_plan_config_unquote value "${BASH_REMATCH[2]}"
    __values_ref[$raw_key]="$value"
    __file_lines_ref[$raw_key]="$lineno"
  done <"$file"
}

__cog_plan_config_apply_file() {
  local config_name="$1" source_name="$2" line_name="$3" file="$4" provenance="$5"
  local -n __config_ref="$config_name"
  local -n __source_ref="$source_name"
  local -n __line_ref="$line_name"
  local -A file_values=()
  local -A file_lines=()
  local k
  [[ -r $file ]] || return 0
  __cog_plan_config_scan_file file_values file_lines "$file"
  for k in COG_PLAN_HOME COG_PLAN_ROOT COG_PLAN_STORE COG_PLAN_LOCAL_DIR COG_PLAN_TRUST COG_PLAN_CEILING COG_PLAN_PROJECT COG_PROJECT_ROOT; do
    if [[ -n ${file_values[$k]+x} ]]; then
      __config_ref[$k]="${file_values[$k]}"
      __source_ref[$k]="${provenance}:${file}"
      __line_ref[$k]="${file_lines[$k]:-}"
    fi
  done
}

__cog_plan_config_find_project_file() {
  local start="${1:-}" current ceiling="${2:-${COG_PLAN_CEILING:-}}" parent
  [[ -n $start ]] || start="$(pwd -P)"
  [[ -d $start ]] || return 0
  current="$(cd -P "$start" && pwd)"
  if [[ -n $ceiling && -d $ceiling ]]; then
    ceiling="$(cd -P "$ceiling" && pwd)"
  fi

  while :; do
    if [[ -f ${current}/.cog/config.sh ]]; then
      printf '%s\n' "${current}/.cog/config.sh"
      return 0
    fi
    [[ -n $ceiling && $current == "$ceiling" ]] && return 0
    parent="$(dirname "$current")"
    [[ $parent == "$current" ]] && return 0
    current="$parent"
  done
}

__cog_plan_config_validate() {
  local config_name="$1" source_name="$2"
  # shellcheck disable=SC2178 # Nameref to the caller's associative array; read-only here.
  local -n __config_ref="$config_name"
  # shellcheck disable=SC2178 # Nameref to the caller's associative array; read-only here.
  local -n __source_ref="$source_name"
  case "${__config_ref[COG_PLAN_STORE]}" in
    auto | local | global) ;;
    *)
      cog::fn::error_raise "InvalidConfigValue" \
        "invalid plan store value" "key=COG_PLAN_STORE value=${__config_ref[COG_PLAN_STORE]} source=${__source_ref[COG_PLAN_STORE]}" \
        "expected auto, local, or global" "correct the plan config value"
      ;;
  esac
  case "${__config_ref[COG_PLAN_TRUST]}" in
    strict | prompt | off) ;;
    *)
      cog::fn::error_raise "InvalidConfigValue" \
        "invalid plan trust value" "key=COG_PLAN_TRUST value=${__config_ref[COG_PLAN_TRUST]} source=${__source_ref[COG_PLAN_TRUST]}" \
        "expected strict, prompt, or off" "correct the plan config value"
      ;;
  esac
}

cog::fn::plan_config_load() {
  local project_root="${1:-}"
  local config_name="${2:-__cog_plan_config}"
  local source_name="${3:-__cog_plan_config_source}"
  local line_name="${4:-__cog_plan_config_line}"
  local -n __config="$config_name"
  local -n __source="$source_name"
  local -n __line="$line_name"
  local xdg_config_home="${XDG_CONFIG_HOME:-$HOME/.config}" user_file overlay project_file k

  __config=(
    [COG_PLAN_HOME]="${COG_PLAN_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/cog/plans}"
    [COG_PLAN_ROOT]=""
    [COG_PLAN_STORE]="auto"
    [COG_PLAN_LOCAL_DIR]=".cog/plans"
    [COG_PLAN_TRUST]="strict"
    [COG_PLAN_CEILING]=""
    [COG_PLAN_PROJECT]=""
    [COG_PROJECT_ROOT]=""
  )
  __source=(
    [COG_PLAN_HOME]="default"
    [COG_PLAN_ROOT]="default"
    [COG_PLAN_STORE]="default"
    [COG_PLAN_LOCAL_DIR]="default"
    [COG_PLAN_TRUST]="default"
    [COG_PLAN_CEILING]="default"
    [COG_PLAN_PROJECT]="default"
    [COG_PROJECT_ROOT]="default"
  )
  __line=(
    [COG_PLAN_HOME]=""
    [COG_PLAN_ROOT]=""
    [COG_PLAN_STORE]=""
    [COG_PLAN_LOCAL_DIR]=""
    [COG_PLAN_TRUST]=""
    [COG_PLAN_CEILING]=""
    [COG_PLAN_PROJECT]=""
    [COG_PROJECT_ROOT]=""
  )

  user_file="${xdg_config_home}/cog/config.sh"
  __cog_plan_config_apply_file "$config_name" "$source_name" "$line_name" "$user_file" "user"
  shopt -s nullglob
  for overlay in "${xdg_config_home}"/cog/conf.d/*.sh; do
    __cog_plan_config_apply_file "$config_name" "$source_name" "$line_name" "$overlay" "user-overlay"
  done
  shopt -u nullglob

  # Resolve the walk ceiling from the env var (knowable pre-walk, highest
  # priority) else the user/overlay config layers already applied above; a
  # project .cog/config.sh cannot bound the search that discovers it.
  local walk_ceiling="${COG_PLAN_CEILING:-${__config[COG_PLAN_CEILING]}}"
  project_file="$(__cog_plan_config_find_project_file "$project_root" "$walk_ceiling")"
  [[ -z $project_file ]] || __cog_plan_config_apply_file "$config_name" "$source_name" "$line_name" "$project_file" "project"

  for k in COG_PLAN_HOME COG_PLAN_ROOT COG_PLAN_STORE COG_PLAN_LOCAL_DIR COG_PLAN_TRUST COG_PLAN_CEILING COG_PLAN_PROJECT COG_PROJECT_ROOT; do
    if [[ -n ${!k:-} ]]; then
      __config[$k]="${!k}"
      __source[$k]="env:${k}"
      __line[$k]=""
    fi
  done

  __cog_plan_config_validate "$config_name" "$source_name"
}

cog::fn::plan_config_sources_json() {
  local config_name="$1" source_name="$2"
  # shellcheck disable=SC2178 # Nameref to the caller's associative array; read-only here.
  local -n __config_ref="$config_name"
  # shellcheck disable=SC2178 # Nameref to the caller's associative array; read-only here.
  local -n __source_ref="$source_name"
  jq -n \
    --arg store "${__config_ref[COG_PLAN_STORE]}" \
    --arg store_source "${__source_ref[COG_PLAN_STORE]}" \
    --arg plan_root "${__config_ref[COG_PLAN_ROOT]}" \
    --arg plan_root_source "${__source_ref[COG_PLAN_ROOT]}" \
    --arg plan_home "${__config_ref[COG_PLAN_HOME]}" \
    --arg plan_home_source "${__source_ref[COG_PLAN_HOME]}" \
    --arg trust "${__config_ref[COG_PLAN_TRUST]}" \
    --arg trust_source "${__source_ref[COG_PLAN_TRUST]}" \
    '{store: $store, store_source: $store_source, plan_root: $plan_root,
      plan_root_source: $plan_root_source, plan_home: $plan_home,
      plan_home_source: $plan_home_source, trust: $trust, trust_source: $trust_source}'
}
