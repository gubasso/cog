# shellcheck shell=bash
: 'desc: Assert required cog subcommands are installed.'

__cog_require_usage() {
  cog::fn::ui_data "Usage: cog require [--json] <subcommand>..."
}

__cog_require_command_path() {
  local name="$1"
  local derived="${name//-/_}"
  cog::fn::ui_dataf '%s/commands/cmd_%s.sh\n' "$LIB_DIR" "$derived"
}

__cog_require_json_array() {
  if (($# == 0)); then
    jq -cn '[]'
  else
    printf '%s\n' "$@" | jq -R . | jq -s .
  fi
}

__cog_require_build_json() {
  local ok="$1"
  shift
  local present_count="$1"
  shift
  local -a present=("${@:1:present_count}")
  shift "$present_count"
  local -a missing=("$@")

  jq -cn \
    --argjson ok "$ok" \
    --argjson present "$(__cog_require_json_array "${present[@]}")" \
    --argjson missing "$(__cog_require_json_array "${missing[@]}")" \
    '{ok: $ok, present: $present, missing: $missing}'
}

cog::cmd::require() {
  local json="${COG_UI_JSON:-false}"
  local name ok json_out
  local -a names=() present=() missing=()

  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_require_usage
        return 0
        ;;
      --json)
        json=true
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown require option" "option: $1" "" "run 'cog require --help'"
        ;;
      *)
        names+=("$1")
        shift
        ;;
    esac
  done

  ((${#names[@]} > 0)) || cog::fn::error_raise "MissingArgument" \
    "missing required subcommand" "usage: cog require [--json] <subcommand>..." "" \
    "run 'cog require --help'"

  for name in "${names[@]}"; do
    if [[ -f $(__cog_require_command_path "$name") ]]; then
      present+=("$name")
    else
      missing+=("$name")
    fi
  done

  ok=true
  ((${#missing[@]} == 0)) || ok=false

  if [[ $json == true ]]; then
    json_out="$(__cog_require_build_json "$ok" "${#present[@]}" "${present[@]}" "${missing[@]}")"
    cog::fn::json_emit 'has("ok") and (.present | type == "array") and (.missing | type == "array")' "$json_out"
  else
    for name in "${missing[@]}"; do
      cog::fn::ui_human "MISSING $name"
    done
  fi

  [[ $ok == true ]]
}
