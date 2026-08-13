# shellcheck shell=bash
: 'desc: Gate whether an input is a reviewable implementation plan.'

__cog_plan_gate_usage() {
  cog::fn::ui_data "Usage: cog plan-gate check (<plan-file>|<plan-dir>|--input-file <abs>) [--json]"
}

__cog_plan_gate_check() {
  local target="" input_file="" json_mode=false
  local classified mode abs json

  while (($# > 0)); do
    case "$1" in
      --input-file)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" \
          "missing plan-gate input file" "option: --input-file" "" "run 'cog plan-gate --help'"
        input_file="$2"
        shift 2
        ;;
      --json)
        json_mode=true
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown plan-gate check option" "option: $1" "" "run 'cog plan-gate --help'"
        ;;
      *)
        [[ -z $target ]] || cog::fn::error_raise "InvalidInput" \
          "too many plan-gate check arguments" "argument: $1" "" "run 'cog plan-gate --help'"
        target="$1"
        shift
        ;;
    esac
  done

  if [[ -n $input_file ]]; then
    [[ -z $target ]] || cog::fn::error_raise "InvalidInput" \
      "plan-gate check takes a path or --input-file, not both" "argument: ${target}" "" \
      "pass one input form"
    cog::fn::plan_artifact::require_absolute_path "$input_file" "input-file"
    mode="inline"
    abs="$input_file"
  else
    [[ -n $target ]] || cog::fn::error_raise "MissingArgument" \
      "missing plan-gate target" "usage: cog plan-gate check <plan-file|plan-dir>" "" \
      "pass a plan file, a plan directory, or --input-file <abs>"
    classified="$(cog::fn::plan_gate::classify_input "$target")"
    mode="${classified%%$'\t'*}"
    abs="${classified#*$'\t'}"
    [[ $mode != inline ]] || cog::fn::error_raise "InputNotFound" \
      "plan-gate target does not exist" "path: ${target}" "" \
      "pass an existing plan file or directory, or stage inline text and pass --input-file <abs>"
  fi

  json="$(cog::fn::plan_gate::check_json "$mode" "$abs")"
  if [[ $json_mode == true || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$(cog::fn::plan_gate::self_check)" "$json"
    jq -e '.ok == true' <<<"$json" >/dev/null || return "$EX_DATAERR"
    return 0
  fi

  cog::fn::ui_data "PLAN_GATE=$(jq -r '.verdict' <<<"$json")"
  cog::fn::ui_data "MODE=$(jq -r '.mode' <<<"$json")"
  cog::fn::ui_data "SOURCES=$(jq -r '.sources | join(" ")' <<<"$json")"
  cog::fn::ui_data "REASON=$(jq -r '.reason' <<<"$json")"
  jq -e '.ok == true' <<<"$json" >/dev/null || cog::fn::error_raise "InvalidInput" \
    "input is not a reviewable implementation plan" "mode: ${mode}" \
    "$(jq -r '.reason' <<<"$json")" \
    "ask the user to build a plan first (/plan-oneshot, /plan-multi, or /plan-vetted)"
}

cog::cmd::plan_gate() {
  local mode="${1:-}"

  case "$mode" in
    -h | --help)
      __cog_plan_gate_usage
      ;;
    check)
      shift
      __cog_plan_gate_check "$@"
      ;;
    "")
      cog::fn::error_raise "MissingArgument" \
        "missing plan-gate mode" "usage: cog plan-gate check" "" "run 'cog plan-gate --help'"
      ;;
    *)
      cog::fn::error_raise "InvalidInput" \
        "unknown plan-gate mode" "mode: ${mode}" "" "run 'cog plan-gate --help'"
      ;;
  esac
}
