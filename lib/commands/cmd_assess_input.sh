# shellcheck shell=bash
: 'desc: Extract input-quality signals and persist the executor gate verdict.'

__cog_assess_input_record_self_check='(.schema=="cog.assess-input.v1") and (.ok==true) and (.route|type=="string")'
__cog_assess_input_validate_self_check='(.schema=="cog.assess-input.validate.v1") and (.ok|type=="boolean") and (.path|type=="string")'

__cog_assess_input_usage() {
  cog::fn::ui_data "Usage: cog assess-input facts [--input-file <path>] [--file <plan-path> ...] [--json]"
  cog::fn::ui_data "Usage: cog assess-input record --run-dir <dir> --route <needs-plan|good-input> --confidence <high|medium|low> --rationale <text> [--signal <key=value> ...] [--out <path>] [--json]"
  cog::fn::ui_data "Usage: cog assess-input validate <path> [--json]"
}

__cog_assess_input_facts() {
  local input_file="" json="${COG_UI_JSON:-false}" result
  local -a files=()

  while (($# > 0)); do
    case "$1" in
      --input-file)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" \
          "missing assess-input input file" "option: --input-file" "" "run 'cog assess-input --help'"
        input_file="$2"
        shift 2
        ;;
      --file)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" \
          "missing assess-input file" "option: --file" "" "run 'cog assess-input --help'"
        files+=("$2")
        shift 2
        ;;
      --json)
        json=true
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" "unknown assess-input facts option" "option: $1" "" \
          "run 'cog assess-input --help'"
        ;;
      *)
        cog::fn::error_raise "TooManyArguments" "too many assess-input facts arguments" "argument: $1" "" \
          "run 'cog assess-input --help'"
        ;;
    esac
  done

  result="$(cog::fn::assess_input::facts_json "$input_file" "${files[@]}")"
  if [[ $json == true ]]; then
    cog::fn::json_emit "$(cog::fn::assess_input::facts_self_check)" "$result"
  else
    cog::fn::ui_data "PLAN_FILES=$(jq -r '.totals.plan_files' <<<"$result")"
    cog::fn::ui_data "READABLE_PLAN_FILES=$(jq -r '.totals.readable_plan_files' <<<"$result")"
    cog::fn::ui_data "MAX_HEADING_COUNT=$(jq -r '.totals.max_heading_count' <<<"$result")"
    cog::fn::ui_data "TOTAL_PLAN_BYTES=$(jq -r '.totals.total_plan_bytes' <<<"$result")"
  fi
}

__cog_assess_input_record() {
  local run_dir="" route="" confidence="" rationale="" out="" json="${COG_UI_JSON:-false}"
  local signals_json='{}' verdict_json
  local -a signal_pairs=()

  while (($# > 0)); do
    case "$1" in
      --run-dir)
        [[ $# -ge 2 && -n ${2:-} && -z $run_dir ]] || cog::fn::error_raise "MissingArgument" \
          "missing run directory" "option: --run-dir" "" "run 'cog assess-input --help'"
        run_dir="$2"
        shift 2
        ;;
      --route)
        [[ $# -ge 2 && -n ${2:-} && -z $route ]] || cog::fn::error_raise "MissingArgument" \
          "missing route" "option: --route" "" "run 'cog assess-input --help'"
        route="$2"
        shift 2
        ;;
      --confidence)
        [[ $# -ge 2 && -n ${2:-} && -z $confidence ]] || cog::fn::error_raise "MissingArgument" \
          "missing confidence" "option: --confidence" "" "run 'cog assess-input --help'"
        confidence="$2"
        shift 2
        ;;
      --rationale)
        [[ $# -ge 2 && -n ${2:-} && -z $rationale ]] || cog::fn::error_raise "MissingArgument" \
          "missing rationale" "option: --rationale" "" "run 'cog assess-input --help'"
        rationale="$2"
        shift 2
        ;;
      --signal)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" \
          "missing signal" "option: --signal" "" "run 'cog assess-input --help'"
        [[ $2 == *=* ]] || cog::fn::error_raise "InvalidInput" \
          "invalid assess-input signal" "signal: $2" "expected key=value" "pass --signal key=value"
        signal_pairs+=("$2")
        shift 2
        ;;
      --out)
        [[ $# -ge 2 && -n ${2:-} && -z $out ]] || cog::fn::error_raise "MissingArgument" \
          "missing output path" "option: --out" "" "run 'cog assess-input --help'"
        out="$2"
        shift 2
        ;;
      --json)
        json=true
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" "unknown assess-input record option" "option: $1" "" \
          "run 'cog assess-input --help'"
        ;;
      *)
        cog::fn::error_raise "TooManyArguments" "too many assess-input record arguments" "argument: $1" "" \
          "run 'cog assess-input --help'"
        ;;
    esac
  done

  [[ -n $run_dir && -n $route && -n $confidence && -n $rationale ]] \
    || cog::fn::error_raise "MissingArgument" \
      "missing assess-input record argument" \
      "usage: cog assess-input record --run-dir <dir> --route <needs-plan|good-input> --confidence <high|medium|low> --rationale <text>" "" \
      "run 'cog assess-input --help'"
  [[ -d $run_dir ]] || cog::fn::error_raise "InputNotFound" \
    "assess-input run directory not found" "path: ${run_dir}" "" "check --run-dir"

  local pair key value
  for pair in "${signal_pairs[@]}"; do
    key="${pair%%=*}"
    value="${pair#*=}"
    signals_json="$(jq -c --arg k "$key" --arg v "$value" '. + {($k): $v}' <<<"$signals_json")"
  done

  verdict_json="$(cog::fn::assess_input::verdict_json "$route" "$confidence" "$rationale" "$signals_json")"
  [[ -n $out ]] || out="$(cog::fn::rundir_path "$run_dir" assess-input.json)"

  if [[ $json == true ]]; then
    cog::fn::json_write_fragment "$out" "$(cog::fn::assess_input::verdict_self_check)" "$verdict_json" >/dev/null
    cog::fn::json_emit "$__cog_assess_input_record_self_check" "$verdict_json"
  else
    cog::fn::json_write_fragment "$out" "$(cog::fn::assess_input::verdict_self_check)" "$verdict_json"
    cog::fn::ui_data "ROUTE=${route}"
  fi
}

__cog_assess_input_validate() {
  local path="" json="${COG_UI_JSON:-false}" ok=true result

  while (($# > 0)); do
    case "$1" in
      --json)
        json=true
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" "unknown assess-input validate option" "option: $1" "" \
          "run 'cog assess-input --help'"
        ;;
      *)
        [[ -z $path ]] || cog::fn::error_raise "TooManyArguments" \
          "too many assess-input validate arguments" "argument: $1" "" "run 'cog assess-input --help'"
        path="$1"
        shift
        ;;
    esac
  done

  [[ -n $path ]] || cog::fn::error_raise "MissingArgument" \
    "missing assess-input verdict path" "usage: cog assess-input validate <path>" "" \
    "run 'cog assess-input --help'"
  if [[ ! -f $path || ! -r $path ]] \
    || ! jq -e "$(cog::fn::assess_input::verdict_self_check)" "$path" >/dev/null 2>&1; then
    ok=false
  fi

  result="$(jq -cn --argjson ok "$ok" --arg path "$path" \
    '{schema: "cog.assess-input.validate.v1", ok: $ok, path: $path}')"
  if [[ $json == true ]]; then
    cog::fn::json_emit "$__cog_assess_input_validate_self_check" "$result"
    [[ $ok == true ]] || return "$EX_DATAERR"
  else
    cog::fn::ui_data "ASSESS_INPUT_PATH=${path}"
    if [[ $ok == true ]]; then
      cog::fn::ui_data "ASSESS_INPUT_VALID"
    else
      cog::fn::error_raise "InvalidInput" "assess-input verdict failed validation" \
        "path: ${path}" "" "regenerate the verdict with 'cog assess-input record'"
    fi
  fi
}

cog::cmd::assess_input() {
  local mode="${1:-}"

  case "$mode" in
    -h | --help)
      __cog_assess_input_usage
      ;;
    facts)
      shift
      __cog_assess_input_facts "$@"
      ;;
    record)
      shift
      __cog_assess_input_record "$@"
      ;;
    validate)
      shift
      __cog_assess_input_validate "$@"
      ;;
    "")
      cog::fn::error_raise "MissingArgument" \
        "missing assess-input mode" "usage: cog assess-input facts|record|validate" "" \
        "run 'cog assess-input --help'"
      ;;
    *)
      cog::fn::error_raise "InvalidInput" \
        "unknown assess-input mode" "mode: ${mode}" "" "run 'cog assess-input --help'"
      ;;
  esac
}
