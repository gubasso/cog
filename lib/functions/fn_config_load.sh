# shellcheck shell=bash

# The [$key] subscripts below index associative arrays with a string key, so
# the $ is required; shellcheck misclassifies them as arithmetic contexts.
# shellcheck disable=SC2004

__cog_config_is_allowed_key() {
  case "$1" in
    json | dry_run | log_level)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

__cog_config_var_to_key() {
  case "$1" in
    COG_JSON)
      printf '%s\n' "json"
      ;;
    COG_DRY_RUN)
      printf '%s\n' "dry_run"
      ;;
    COG_LOG_LEVEL)
      printf '%s\n' "log_level"
      ;;
    *)
      return 1
      ;;
  esac
}

__cog_config_normalize_bool() {
  local -n __out="$1"
  local key="$2"
  local value="$3"
  local source="$4"
  local lowered="${value,,}"

  case "$lowered" in
    true | 1 | yes | on)
      __out=true
      ;;
    false | 0 | no | off)
      __out=false
      ;;
    *)
      cog::helpers::die "$EX_CONFIG" "InvalidConfigValue" \
        "invalid config value" "key=${key} value=${value} source=${source}" \
        "expected boolean true/false/1/0/yes/no/on/off" "correct the config value"
      ;;
  esac
}

__cog_config_normalize_log_level() {
  local -n __out="$1"
  local value="$2"
  local source="$3"
  local lowered="${value,,}"

  case "$lowered" in
    warn | info | debug | trace)
      __out="$lowered"
      ;;
    *)
      cog::helpers::die "$EX_CONFIG" "InvalidConfigValue" \
        "invalid config value" "key=log_level value=${value} source=${source}" \
        "expected warn, info, debug, or trace" "correct the config value"
      ;;
  esac
}

__cog_config_apply_value() {
  local -n __config_ref="$1"
  local -n __source_ref="$2"
  local -n __line_ref="$3"
  local key="$4"
  local value="$5"
  local provenance="$6"
  local lineno="${7:-}"

  case "$key" in
    json | dry_run)
      __cog_config_normalize_bool value "$key" "$value" "$provenance"
      ;;
    log_level)
      __cog_config_normalize_log_level value "$value" "$provenance"
      ;;
  esac

  __config_ref[$key]="$value"
  __source_ref[$key]="$provenance"
  __line_ref[$key]="$lineno"
}

# Strip one layer of matching surrounding quotes from a config value token and
# return the literal inner text. The scanner has already proven the token is a
# safe literal form, so no expansion can occur here.
__cog_config_unquote() {
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

# Parse a config file WITHOUT sourcing it. Config files are never executed as
# shell: each non-blank, non-comment, non-desc line must match a single
# anchored literal assignment (allowed key, '=', then one literal scalar token
# that is a double/single-quoted string with no expansion characters or a bare
# token of safe literal characters). Any other content — command separators,
# redirections, trailing command words, expansions, substitutions, multiple
# statements — fails closed. This eliminates the shell-injection class entirely
# rather than blocklisting individual dangerous substrings, since an
# attacker-controlled ${PWD}/.cog/config.sh must never run code.
#
# Populates two namerefs keyed by canonical config key: parsed value and source
# line number.
__cog_config_scan_file() {
  local -n __values_ref="$1"
  local -n __file_lines_ref="$2"
  local file="$3"
  local lineno=0
  local line raw_key key value
  # Anchored grammar: optional WS, key, optional WS, '=', optional WS, value, optional WS, EOL.
  # value := "<no $ ` \ ">" | '<no '>' | <bare safe literal chars>
  local key_re='(COG_JSON|COG_DRY_RUN|COG_LOG_LEVEL|json|dry_run|log_level|[A-Za-z_][A-Za-z0-9_]*)'
  local val_re='("[^"$`\\]*"|'\''[^'\'']*'\''|[A-Za-z0-9_.:/+-]+)'
  local assign_re="^[[:space:]]*${key_re}[[:space:]]*=[[:space:]]*${val_re}[[:space:]]*$"

  __values_ref=()
  __file_lines_ref=()

  while IFS= read -r line || [[ -n $line ]]; do
    lineno=$((lineno + 1))
    [[ $line =~ ^[[:space:]]*$ ]] && continue
    [[ $line =~ ^[[:space:]]*# ]] && continue
    [[ $line =~ ^[[:space:]]*:\ \'desc:\ .+\'[[:space:]]*$ ]] && continue

    if [[ ! $line =~ $assign_re ]]; then
      cog::helpers::die "$EX_CONFIG" "InvalidConfigStatement" \
        "config line is not a single literal assignment" "where: ${file}:${lineno}" \
        "config files may only assign json, dry_run, or log_level to a literal value" \
        "use a plain literal assignment such as json=true; cog config files are not shell scripts"
    fi

    raw_key="${BASH_REMATCH[1]}"
    key="$(__cog_config_var_to_key "$raw_key" 2>/dev/null || printf '%s\n' "$raw_key")"
    if ! __cog_config_is_allowed_key "$key"; then
      cog::helpers::die "$EX_CONFIG" "UnknownConfigKey" \
        "unknown config key" "where: ${file}:${lineno} key=${key}" \
        "only json, dry_run, log_level are valid in this version" "remove or correct the key"
    fi

    __cog_config_unquote value "${BASH_REMATCH[2]}"
    __values_ref[$key]="$value"
    __file_lines_ref[$key]="$lineno"
  done <"$file"
}

__cog_config_load_file() {
  local config_name="$1"
  local source_name="$2"
  local line_name="$3"
  local file="$4"
  local provenance="$5"
  local -A file_values=()
  local -A file_lines=()
  local k

  [[ -r $file ]] || return 0

  __cog_config_scan_file file_values file_lines "$file"

  for k in json dry_run log_level; do
    [[ -n ${file_values[$k]+x} ]] && __cog_config_apply_value "$config_name" "$source_name" "$line_name" \
      "$k" "${file_values[$k]}" "$provenance" "${file_lines[$k]:-}"
  done

  return 0
}

cog::fn::config_load() {
  local ctx_name="$1"
  local config_name="$2"
  local source_name="$3"
  local line_name="$4"
  local -n __ctx="$ctx_name"
  local -n __config="$config_name"
  local -n __source="$source_name"
  local -n __line="$line_name"

  # The keys below are associative-array elements of the nameref targets, not
  # bare variables; shellcheck misreads them as unassigned references (SC2154).
  # shellcheck disable=SC2154
  __config=(
    [dry_run]=false
    [json]=false
    [log_level]=warn
  )
  __source=(
    [dry_run]=default
    [json]=default
    [log_level]=default
  )
  __line=(
    [dry_run]=""
    [json]=""
    [log_level]=""
  )

  local xdg_config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
  local user_file="${xdg_config_home}/cog/config.sh"
  local overlay
  local project_file="${PWD}/.cog/config.sh"

  __cog_config_load_file "$config_name" "$source_name" "$line_name" "$user_file" "user:${user_file}"

  shopt -s nullglob
  for overlay in "${xdg_config_home}"/cog/conf.d/*.sh; do
    __cog_config_load_file "$config_name" "$source_name" "$line_name" "$overlay" "user-overlay:${overlay}"
  done
  shopt -u nullglob

  __cog_config_load_file "$config_name" "$source_name" "$line_name" "$project_file" "project:${project_file}"

  [[ -n ${COG_JSON:-} ]] && __cog_config_apply_value "$config_name" "$source_name" "$line_name" \
    json "$COG_JSON" "env:COG_JSON" ""
  [[ -n ${COG_DRY_RUN:-} ]] && __cog_config_apply_value "$config_name" "$source_name" "$line_name" \
    dry_run "$COG_DRY_RUN" "env:COG_DRY_RUN" ""
  [[ -n ${COG_LOG_LEVEL:-} ]] && __cog_config_apply_value "$config_name" "$source_name" "$line_name" \
    log_level "$COG_LOG_LEVEL" "env:COG_LOG_LEVEL" ""

  if [[ ${__ctx[cli_set_json]:-false} == true ]]; then
    __cog_config_apply_value "$config_name" "$source_name" "$line_name" json "${__ctx[json]}" "cli:--json" ""
  fi
  if [[ ${__ctx[cli_set_dry_run]:-false} == true ]]; then
    __cog_config_apply_value "$config_name" "$source_name" "$line_name" dry_run "${__ctx[dry_run]}" "cli:--dry-run" ""
  fi
  if [[ ${__ctx[cli_set_log_level]:-false} == true ]]; then
    __cog_config_apply_value "$config_name" "$source_name" "$line_name" \
      log_level "${__ctx[log_level]}" "cli:${__ctx[cli_log_level_flag]}" ""
  fi
}
