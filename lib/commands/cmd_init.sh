# shellcheck shell=bash
: 'desc: Initialize cog runtime directories and prerequisites.'

__cog_init_self_check='(.schema=="cog.init.v1") and (.ok|type=="boolean") and (.dry_run|type=="boolean") and (.created|type=="array") and (.existing|type=="array") and (.failed|type=="array") and (.dirs.config|type=="string") and (.dirs.state|type=="string") and (.dirs.cache|type=="string") and (.dirs.data|type=="string")'

__cog_init_usage() {
  cog::fn::ui_data "Usage: cog init [--dry-run] [--json]"
}

__cog_init_json_array() {
  if (($# == 0)); then
    jq -cn '[]'
  else
    printf '%s\n' "$@" | jq -R . | jq -s .
  fi
}

__cog_init_failed_json_array() {
  if (($# == 0)); then
    jq -cn '[]'
  else
    printf '%s\n' "$@" | jq -s .
  fi
}

__cog_init_failed_object() {
  local name="$1"
  local path="$2"
  local detail="$3"

  jq -cn --arg name "$name" --arg path "$path" --arg detail "$detail" \
    '{name: $name, path: $path, detail: $detail}'
}

# Detect paths that are provably uncreatable without mutating the filesystem:
# the target itself exists as a non-directory, or its nearest existing ancestor
# is a non-directory (so mkdir -p could never produce a directory there).
__cog_init_path_blocked() {
  local path="$1"
  local probe="$path"

  if [[ -e $path && ! -d $path ]]; then
    return 0
  fi

  while [[ $probe == */* ]]; do
    probe="${probe%/*}"
    [[ -z $probe ]] && probe="/"
    if [[ -e $probe ]]; then
      [[ -d $probe ]] && return 1
      return 0
    fi
  done

  return 1
}

__cog_init_build_json() {
  local dry_run="$1"
  local ok=true
  local name path failure_json
  local -A dirs=()
  local -a created=() existing=() failed=()

  cog::fn::prereq_runtime_dirs dirs

  for name in config state cache data; do
    path="${dirs[$name]}"
    if [[ -d $path ]]; then
      existing+=("$path")
    elif [[ $dry_run == true ]]; then
      if __cog_init_path_blocked "$path"; then
        ok=false
        failure_json="$(__cog_init_failed_object "$name" "$path" "runtime directory is not creatable")"
        failed+=("$failure_json")
      else
        created+=("$path")
      fi
    elif mkdir -p "$path" 2>/dev/null && [[ -d $path ]]; then
      created+=("$path")
    else
      ok=false
      failure_json="$(__cog_init_failed_object "$name" "$path" "runtime directory is not creatable")"
      failed+=("$failure_json")
    fi
  done

  jq -n \
    --arg schema "cog.init.v1" \
    --argjson ok "$ok" \
    --argjson dry_run "$dry_run" \
    --arg config_dir "${dirs[config]}" \
    --arg state_dir "${dirs[state]}" \
    --arg cache_dir "${dirs[cache]}" \
    --arg data_dir "${dirs[data]}" \
    --argjson created "$(__cog_init_json_array "${created[@]}")" \
    --argjson existing "$(__cog_init_json_array "${existing[@]}")" \
    --argjson failed "$(__cog_init_failed_json_array "${failed[@]}")" \
    '{schema: $schema, ok: $ok, dry_run: $dry_run,
      dirs: {config: $config_dir, state: $state_dir, cache: $cache_dir, data: $data_dir},
      created: $created, existing: $existing, failed: $failed}'
}

__cog_init_json_array_contains() {
  local json="$1"
  local filter="$2"
  local value="$3"

  jq -e --arg value "$value" "${filter} | index(\$value)" <<<"$json" >/dev/null
}

__cog_init_failed_contains() {
  local json="$1"
  local name="$2"

  jq -e --arg name "$name" '.failed[]? | select(.name == $name)' <<<"$json" >/dev/null
}

__cog_init_emit_plain() {
  local json="$1"
  local dry_run="$2"
  local ok name path

  for name in config state cache data; do
    path="$(jq -r --arg name "$name" '.dirs[$name]' <<<"$json")"
    if __cog_init_failed_contains "$json" "$name"; then
      cog::fn::ui_data "failed ${name} ${path}"
    elif __cog_init_json_array_contains "$json" '.existing' "$path"; then
      cog::fn::ui_data "existing ${name} ${path}"
    elif [[ $dry_run == true ]]; then
      cog::fn::ui_data "would-create ${name} ${path}"
    else
      cog::fn::ui_data "created ${name} ${path}"
    fi
  done

  ok="$(jq -r '.ok' <<<"$json")"
  if [[ $ok == true ]]; then
    cog::fn::ui_data "INIT_OK"
  else
    cog::fn::ui_data "INIT_FAILED config"
  fi
}

cog::cmd::init() {
  local dry_run=false
  local mode=""
  local json

  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_init_usage
        return 0
        ;;
      --dry-run)
        dry_run=true
        shift
        ;;
      --json)
        mode=json
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown init option" "option: $1" "" "run 'cog init --help'"
        ;;
      *)
        cog::fn::error_raise "TooManyArguments" \
          "init takes no positional arguments" "argument: $1" "" "run 'cog init --help'"
        ;;
    esac
  done

  json="$(__cog_init_build_json "$dry_run")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$__cog_init_self_check" "$json"
  else
    __cog_init_emit_plain "$json" "$dry_run"
  fi

  if jq -e '.ok == true' <<<"$json" >/dev/null; then
    return 0
  fi
  return "$EX_CONFIG"
}
