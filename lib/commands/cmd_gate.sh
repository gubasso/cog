# shellcheck shell=bash
: 'desc: Render, check, stamp, and list canonical skill gate stanzas.'

__cog_gate_usage() {
  cog::fn::ui_data "Usage: cog gate render --id <id> --skill <name>"
  cog::fn::ui_data "Usage: cog gate check --id <id> --skill <name> --input <file> [--format text|json]"
  cog::fn::ui_data "Usage: cog gate stamp --id <id> --skill <name> --input <file>"
  cog::fn::ui_data "Usage: cog gate list [--format text|json]"
  cog::fn::ui_data "Usage: cog gate --help"
}

__cog_gate_require_id() {
  local id="$1"
  [[ -n $id ]] || cog::fn::error_raise "MissingArgument" \
    "missing gate id" "option: --id" "" "run 'cog gate --help'"
  cog::fn::gate::is_id "$id" || cog::fn::error_raise "InvalidInput" \
    "unknown gate id" "id: ${id}" "valid ids: $(cog::fn::gate::ids | paste -sd' ' -)" \
    "run 'cog gate list'"
}

__cog_gate_require_name() {
  local name="$1"
  [[ -n $name ]] || cog::fn::error_raise "MissingArgument" \
    "missing skill name" "option: --skill" "" "run 'cog gate --help'"
  cog::fn::skill::name_is_valid "$name" || cog::fn::error_raise "InvalidInput" \
    "invalid skill name" "name: ${name}" "" "use ^[a-z0-9-]{1,64}$ and avoid reserved names anthropic and claude"
}

__cog_gate_render_cmd() {
  local id="" name=""
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_gate_usage
        return 0
        ;;
      --id)
        [[ $# -ge 2 && -n ${2:-} && -z $id ]] || cog::fn::error_raise "MissingArgument" \
          "missing gate id" "option: --id" "" "run 'cog gate --help'"
        id="$2"
        shift 2
        ;;
      --skill)
        [[ $# -ge 2 && -n ${2:-} && -z $name ]] || cog::fn::error_raise "MissingArgument" \
          "missing skill name" "option: --skill" "" "run 'cog gate --help'"
        name="$2"
        shift 2
        ;;
      -*) cog::fn::error_raise "InvalidInput" \
        "unknown gate render option" "option: $1" "" "run 'cog gate --help'" ;;
      *) cog::fn::error_raise "TooManyArguments" \
        "too many gate render arguments" "argument: $1" "" "run 'cog gate --help'" ;;
    esac
  done
  __cog_gate_require_id "$id"
  __cog_gate_require_name "$name"
  cog::fn::gate::render "$id" "$name"
}

__cog_gate_check_cmd() {
  local id="" name="" input="" format="text"
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_gate_usage
        return 0
        ;;
      --id)
        [[ $# -ge 2 && -n ${2:-} && -z $id ]] || cog::fn::error_raise "MissingArgument" \
          "missing gate id" "option: --id" "" "run 'cog gate --help'"
        id="$2"
        shift 2
        ;;
      --skill)
        [[ $# -ge 2 && -n ${2:-} && -z $name ]] || cog::fn::error_raise "MissingArgument" \
          "missing skill name" "option: --skill" "" "run 'cog gate --help'"
        name="$2"
        shift 2
        ;;
      --input)
        [[ $# -ge 2 && -n ${2:-} && -z $input ]] || cog::fn::error_raise "MissingArgument" \
          "missing input file" "option: --input" "" "run 'cog gate --help'"
        input="$2"
        shift 2
        ;;
      --format)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" \
          "missing format" "option: --format" "" "run 'cog gate --help'"
        format="$2"
        shift 2
        ;;
      --json)
        format="json"
        shift
        ;;
      -*) cog::fn::error_raise "InvalidInput" \
        "unknown gate check option" "option: $1" "" "run 'cog gate --help'" ;;
      *) cog::fn::error_raise "TooManyArguments" \
        "too many gate check arguments" "argument: $1" "" "run 'cog gate --help'" ;;
    esac
  done
  __cog_gate_require_id "$id"
  __cog_gate_require_name "$name"
  [[ -n $input ]] || cog::fn::error_raise "MissingArgument" \
    "missing input file" "option: --input" "" "run 'cog gate --help'"
  cog::fn::rundir_require_file "$input" "input file"
  [[ $format == text || $format == json ]] || cog::fn::error_raise "InvalidInput" \
    "unknown format" "format: ${format}" "" "use --format text|json"

  local actual expected status="ok"
  actual="$(cog::fn::gate::normalize "$(cog::fn::gate::extract "$id" "$input")")"
  expected="$(cog::fn::gate::normalize "$(cog::fn::gate::paragraph "$id" "$name")")"
  if [[ -z $actual ]]; then
    status="missing"
  elif [[ $actual != "$expected" ]]; then
    status="drift"
  fi

  if [[ $format == json ]]; then
    local result
    result="$(jq -cn --arg id "$id" --arg skill "$name" --arg input "$input" --arg status "$status" \
      '{ok: ($status == "ok"), id: $id, skill: $skill, input: $input, status: $status}')"
    cog::fn::json_emit '(.status | type == "string")' "$result"
  else
    cog::fn::ui_data "${status} ${id} ${name}"
  fi
  [[ $status == ok ]] || return 1
}

__cog_gate_stamp_cmd() {
  local id="" name="" input=""
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_gate_usage
        return 0
        ;;
      --id)
        [[ $# -ge 2 && -n ${2:-} && -z $id ]] || cog::fn::error_raise "MissingArgument" \
          "missing gate id" "option: --id" "" "run 'cog gate --help'"
        id="$2"
        shift 2
        ;;
      --skill)
        [[ $# -ge 2 && -n ${2:-} && -z $name ]] || cog::fn::error_raise "MissingArgument" \
          "missing skill name" "option: --skill" "" "run 'cog gate --help'"
        name="$2"
        shift 2
        ;;
      --input)
        [[ $# -ge 2 && -n ${2:-} && -z $input ]] || cog::fn::error_raise "MissingArgument" \
          "missing input file" "option: --input" "" "run 'cog gate --help'"
        input="$2"
        shift 2
        ;;
      -*) cog::fn::error_raise "InvalidInput" \
        "unknown gate stamp option" "option: $1" "" "run 'cog gate --help'" ;;
      *) cog::fn::error_raise "TooManyArguments" \
        "too many gate stamp arguments" "argument: $1" "" "run 'cog gate --help'" ;;
    esac
  done
  __cog_gate_require_id "$id"
  __cog_gate_require_name "$name"
  [[ -n $input ]] || cog::fn::error_raise "MissingArgument" \
    "missing input file" "option: --input" "" "run 'cog gate --help'"
  cog::fn::rundir_require_file "$input" "input file"

  cog::fn::gate::stamp "$id" "$name" "$input" >/dev/null || cog::fn::error_raise "JsonWriteFailed" \
    "could not stamp gate" "path: ${input}" "" "check the input path and retry"
  cog::fn::ui_data "STAMPED ${input}"
}

__cog_gate_list_cmd() {
  local format="text" id
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_gate_usage
        return 0
        ;;
      --format)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" \
          "missing format" "option: --format" "" "run 'cog gate --help'"
        format="$2"
        shift 2
        ;;
      --json)
        format="json"
        shift
        ;;
      -*) cog::fn::error_raise "InvalidInput" \
        "unknown gate list option" "option: $1" "" "run 'cog gate --help'" ;;
      *) cog::fn::error_raise "TooManyArguments" \
        "too many gate list arguments" "argument: $1" "" "run 'cog gate --help'" ;;
    esac
  done
  [[ $format == text || $format == json ]] || cog::fn::error_raise "InvalidInput" \
    "unknown format" "format: ${format}" "" "use --format text|json"

  if [[ $format == json ]]; then
    local arr="[]"
    while IFS= read -r id; do
      arr="$(jq -c --arg id "$id" --arg desc "$(cog::fn::gate::description "$id")" \
        '. + [{id: $id, description: $desc}]' <<<"$arr")"
    done < <(cog::fn::gate::ids)
    cog::fn::json_emit '(type == "array")' "$arr"
  else
    while IFS= read -r id; do
      cog::fn::ui_data "${id}	$(cog::fn::gate::description "$id")"
    done < <(cog::fn::gate::ids)
  fi
}

cog::cmd::gate() {
  local verb="${1:-}"
  case "$verb" in
    -h | --help | "")
      __cog_gate_usage
      return 0
      ;;
    render)
      shift
      __cog_gate_render_cmd "$@"
      ;;
    check)
      shift
      __cog_gate_check_cmd "$@"
      ;;
    stamp)
      shift
      __cog_gate_stamp_cmd "$@"
      ;;
    list)
      shift
      __cog_gate_list_cmd "$@"
      ;;
    -*) cog::fn::error_raise "InvalidInput" \
      "unknown gate option" "option: $verb" "" "run 'cog gate --help'" ;;
    *) cog::fn::error_raise "InvalidInput" \
      "unknown gate mode" "mode: $verb" "" "expected render, check, stamp, or list" ;;
  esac
}
