# shellcheck shell=bash
: 'desc: Render canonical ask-skill research-flag instruction paragraphs.'

__cog_ask_flag_usage() {
  cog::fn::ui_data "Usage: cog ask-flag render --flag <key>"
  cog::fn::ui_data "Usage: cog ask-flag list [--format text|json]"
  cog::fn::ui_data "Usage: cog ask-flag --help"
}

__cog_ask_flag_require_id() {
  local id="$1"
  [[ -n $id ]] || cog::fn::error_raise "MissingArgument" \
    "missing flag key" "option: --flag" "" "run 'cog ask-flag --help'"
  cog::fn::ask_flag::is_id "$id" || cog::fn::error_raise "InvalidInput" \
    "unknown ask flag" "flag: ${id}" "valid flags: $(cog::fn::ask_flag::ids | paste -sd' ' -)" \
    "run 'cog ask-flag list'"
}

__cog_ask_flag_render_cmd() {
  local flag=""
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_ask_flag_usage
        return 0
        ;;
      --flag)
        [[ $# -ge 2 && -n ${2:-} && -z $flag ]] || cog::fn::error_raise "MissingArgument" \
          "missing flag key" "option: --flag" "" "run 'cog ask-flag --help'"
        flag="$2"
        shift 2
        ;;
      -*) cog::fn::error_raise "InvalidInput" \
        "unknown ask-flag render option" "option: $1" "" "run 'cog ask-flag --help'" ;;
      *) cog::fn::error_raise "TooManyArguments" \
        "too many ask-flag render arguments" "argument: $1" "" "run 'cog ask-flag --help'" ;;
    esac
  done
  __cog_ask_flag_require_id "$flag"
  cog::fn::ask_flag::render "$flag" || cog::fn::error_raise "InvalidInput" \
    "ask flag has no instruction text" "flag: ${flag}" "" "check data/ask-flags/instructions.yaml"
}

__cog_ask_flag_list_cmd() {
  local format="text" id
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_ask_flag_usage
        return 0
        ;;
      --format)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" \
          "missing format" "option: --format" "" "run 'cog ask-flag --help'"
        format="$2"
        shift 2
        ;;
      --json)
        format="json"
        shift
        ;;
      -*) cog::fn::error_raise "InvalidInput" \
        "unknown ask-flag list option" "option: $1" "" "run 'cog ask-flag --help'" ;;
      *) cog::fn::error_raise "TooManyArguments" \
        "too many ask-flag list arguments" "argument: $1" "" "run 'cog ask-flag --help'" ;;
    esac
  done
  [[ $format == text || $format == json ]] || cog::fn::error_raise "InvalidInput" \
    "unknown format" "format: ${format}" "" "use --format text|json"

  if [[ $format == json ]]; then
    local arr="[]"
    while IFS= read -r id; do
      arr="$(jq -c --arg id "$id" --arg desc "$(cog::fn::ask_flag::description "$id")" \
        '. + [{flag: $id, description: $desc}]' <<<"$arr")"
    done < <(cog::fn::ask_flag::ids)
    cog::fn::json_emit '(type == "array")' "$arr"
  else
    while IFS= read -r id; do
      cog::fn::ui_data "${id}	$(cog::fn::ask_flag::description "$id")"
    done < <(cog::fn::ask_flag::ids)
  fi
}

cog::cmd::ask_flag() {
  local verb="${1:-}"
  case "$verb" in
    -h | --help | "")
      __cog_ask_flag_usage
      return 0
      ;;
    render)
      shift
      __cog_ask_flag_render_cmd "$@"
      ;;
    list)
      shift
      __cog_ask_flag_list_cmd "$@"
      ;;
    -*) cog::fn::error_raise "InvalidInput" \
      "unknown ask-flag option" "option: $verb" "" "run 'cog ask-flag --help'" ;;
    *) cog::fn::error_raise "InvalidInput" \
      "unknown ask-flag mode" "mode: $verb" "" "expected render or list" ;;
  esac
}
