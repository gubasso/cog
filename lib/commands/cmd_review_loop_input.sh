# shellcheck shell=bash
: 'desc: Build and validate review-loop handoff input JSON.'

__cog_review_loop_input_usage() {
  cog::fn::ui_data "Usage: cog review-loop-input build --run-dir <dir> [--context <path>] [--out <path>|--json]"
  cog::fn::ui_data "Usage: cog review-loop-input validate --input <path> [--json]"
  cog::fn::ui_data "Usage: cog review-loop-input --help"
}

__cog_review_loop_input_build_cmd() {
  local run_dir="" context="" out="" json="${COG_UI_JSON:-false}"
  local assembled

  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_review_loop_input_usage
        return 0
        ;;
      --run-dir)
        [[ $# -ge 2 && -n ${2:-} && -z $run_dir ]] || cog::fn::error_raise "MissingArgument" \
          "missing run directory" "option: --run-dir" "" "run 'cog review-loop-input --help'"
        run_dir="$2"
        shift 2
        ;;
      --context)
        [[ $# -ge 2 && -n ${2:-} && -z $context ]] || cog::fn::error_raise "MissingArgument" \
          "missing context brief path" "option: --context" "" "run 'cog review-loop-input --help'"
        context="$2"
        shift 2
        ;;
      --out)
        [[ $# -ge 2 && -n ${2:-} && -z $out && $json != true ]] || cog::fn::error_raise "InvalidInput" \
          "invalid review-loop-input output mode" "option: --out" "" "choose either --out or --json"
        out="$2"
        shift 2
        ;;
      --json)
        [[ -z $out ]] || cog::fn::error_raise "InvalidInput" \
          "invalid review-loop-input output mode" "option: --json" "" "choose either --out or --json"
        json=true
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown review-loop-input build option" "option: $1" "" "run 'cog review-loop-input --help'"
        ;;
      *)
        cog::fn::error_raise "TooManyArguments" \
          "too many review-loop-input build arguments" "argument: $1" "" "run 'cog review-loop-input --help'"
        ;;
    esac
  done

  [[ -n $run_dir ]] || cog::fn::error_raise "MissingArgument" \
    "missing run directory" "usage: cog review-loop-input build --run-dir <dir> [--out <path>|--json]" "" \
    "run 'cog review-loop-input --help'"

  local self_check
  self_check="$(cog::fn::review_loop_input_schema_filter)"
  assembled="$(cog::fn::review_loop_input_build "$run_dir" "$context")"
  if [[ $json == true ]]; then
    cog::fn::json_emit "$self_check" "$assembled"
  else
    [[ -n $out ]] || out="$(cog::fn::review_loop_input_default_path "$run_dir")"
    cog::fn::json_write_fragment "$out" "$self_check" "$assembled"
  fi
}

__cog_review_loop_input_validate_cmd() {
  local input="" json="${COG_UI_JSON:-false}" result

  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_review_loop_input_usage
        return 0
        ;;
      --input)
        [[ $# -ge 2 && -n ${2:-} && -z $input ]] || cog::fn::error_raise "MissingArgument" \
          "missing review-loop input file" "option: --input" "" "run 'cog review-loop-input --help'"
        input="$2"
        shift 2
        ;;
      --json)
        json=true
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown review-loop-input validate option" "option: $1" "" "run 'cog review-loop-input --help'"
        ;;
      *)
        cog::fn::error_raise "TooManyArguments" \
          "too many review-loop-input validate arguments" "argument: $1" "" "run 'cog review-loop-input --help'"
        ;;
    esac
  done

  [[ -n $input ]] || cog::fn::error_raise "MissingArgument" \
    "missing review-loop input file" "usage: cog review-loop-input validate --input <path> [--json]" "" \
    "run 'cog review-loop-input --help'"

  cog::fn::review_loop_input_validate_file "$input"
  result="$(jq -cn --arg input "$input" '{ok: true, input: $input}')"
  if [[ $json == true ]]; then
    cog::fn::json_emit '(.ok == true) and (.input | type == "string")' "$result"
  else
    cog::fn::ui_data "$result"
  fi
}

cog::cmd::review_loop_input() {
  local verb="${1:-}"

  case "$verb" in
    -h | --help | "")
      __cog_review_loop_input_usage
      [[ -n $verb ]] || return 0
      return 0
      ;;
    build)
      shift
      __cog_review_loop_input_build_cmd "$@"
      ;;
    validate)
      shift
      __cog_review_loop_input_validate_cmd "$@"
      ;;
    -*)
      cog::fn::error_raise "InvalidInput" \
        "unknown review-loop-input option" "option: $verb" "" "run 'cog review-loop-input --help'"
      ;;
    *)
      cog::fn::error_raise "InvalidInput" \
        "unknown review-loop-input mode" "mode: $verb" "" "expected build or validate"
      ;;
  esac
}
