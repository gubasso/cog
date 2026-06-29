# shellcheck shell=bash
: 'desc: Extract and compare implementation plan complexity signals.'

__cog_plan_complexity_extract_self_check='(.schema=="cog.plan-complexity.extract.v1") and (.ok == true) and (.path|type=="string") and (.input_kind|IN("plan","round","fragment")) and (.signals|type=="object")'
__cog_plan_complexity_ceiling_self_check='(.schema=="cog.plan-complexity.ceiling.v1") and (.ok == true) and (.ceiling|type=="string") and (.rank|type=="number") and (.valid_grades|type=="array")'
__cog_plan_complexity_over_self_check='(.schema=="cog.plan-complexity.over-ceiling.v1") and (.ok == true) and (.grade|type=="string") and (.ceiling|type=="string") and (.over|type=="boolean")'

__cog_plan_complexity_usage() {
  cog::fn::ui_data "Usage: cog plan-complexity extract <path> (--json|<out.json>)"
  # shellcheck disable=SC2016
  cog::fn::ui_data 'Usage: cog plan-complexity ceiling --json  (honors $COG_PLAN_COMPLEXITY_CEILING; defaults to Very High)'
  cog::fn::ui_data "Usage: cog plan-complexity over-ceiling --grade <grade> --json"
}

__cog_plan_complexity_emit() {
  local json="$1" check="$2" mode="$3" out="${4:-}"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$check" "$json"
  else
    cog::fn::json_write_fragment "$out" "$check" "$json"
  fi
}

__cog_plan_complexity_extract() {
  local path="" mode="" out="" json
  while (($# > 0)); do
    case "$1" in
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" "duplicate output mode" "" "" "choose --json or an output path"
        mode=json
        shift
        ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown plan-complexity extract option" "option: $1" "" "run 'cog plan-complexity --help'" ;;
      *)
        if [[ -z $path ]]; then path="$1"; elif [[ -z $mode ]]; then
          out="$1"
          # shellcheck disable=SC2209
          mode=file
        else cog::fn::error_raise "TooManyArguments" "too many extract arguments" "argument: $1" "" "run 'cog plan-complexity --help'"; fi
        shift
        ;;
    esac
  done
  [[ -n $path ]] || cog::fn::error_raise "MissingArgument" "missing extract path" "usage: cog plan-complexity extract <path> (--json|<out.json>)" "" "run 'cog plan-complexity --help'"
  [[ -n $mode || ${COG_UI_JSON:-false} == true ]] || cog::fn::error_raise "MissingArgument" "missing extract output mode" "usage: cog plan-complexity extract <path> (--json|<out.json>)" "" "run 'cog plan-complexity --help'"
  [[ -n $mode ]] || mode=json
  json="$(cog::fn::plan_complexity::extract_json "$path")"
  __cog_plan_complexity_emit "$json" "$__cog_plan_complexity_extract_self_check" "$mode" "$out"
}

__cog_plan_complexity_ceiling() {
  local mode="" json
  while (($# > 0)); do
    case "$1" in
      --json)
        mode=json
        shift
        ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown plan-complexity ceiling option" "option: $1" "" "run 'cog plan-complexity --help'" ;;
      *) cog::fn::error_raise "TooManyArguments" "too many ceiling arguments" "argument: $1" "" "run 'cog plan-complexity --help'" ;;
    esac
  done
  [[ -n $mode || ${COG_UI_JSON:-false} == true ]] || cog::fn::error_raise "MissingArgument" "missing ceiling output mode" "usage: cog plan-complexity ceiling --json" "" "run 'cog plan-complexity --help'"
  json="$(cog::fn::plan_complexity::ceiling_json)"
  __cog_plan_complexity_emit "$json" "$__cog_plan_complexity_ceiling_self_check" json
}

__cog_plan_complexity_over_ceiling() {
  local grade="" mode="" json
  while (($# > 0)); do
    case "$1" in
      --grade)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" "missing grade" "option: --grade" "" "run 'cog plan-complexity --help'"
        grade="$2"
        shift 2
        ;;
      --json)
        mode=json
        shift
        ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown plan-complexity over-ceiling option" "option: $1" "" "run 'cog plan-complexity --help'" ;;
      *) cog::fn::error_raise "TooManyArguments" "too many over-ceiling arguments" "argument: $1" "" "run 'cog plan-complexity --help'" ;;
    esac
  done
  [[ -n $grade ]] || cog::fn::error_raise "MissingArgument" "missing over-ceiling grade" "option: --grade" "" "run 'cog plan-complexity --help'"
  [[ -n $mode || ${COG_UI_JSON:-false} == true ]] || cog::fn::error_raise "MissingArgument" "missing over-ceiling output mode" "usage: cog plan-complexity over-ceiling --grade <grade> --json" "" "run 'cog plan-complexity --help'"
  json="$(cog::fn::plan_complexity::over_ceiling_json "$grade")"
  __cog_plan_complexity_emit "$json" "$__cog_plan_complexity_over_self_check" json
}

cog::cmd::plan_complexity() {
  local mode="${1:-}"
  case "$mode" in
    -h | --help) __cog_plan_complexity_usage ;;
    extract)
      shift
      __cog_plan_complexity_extract "$@"
      ;;
    ceiling)
      shift
      __cog_plan_complexity_ceiling "$@"
      ;;
    over-ceiling)
      shift
      __cog_plan_complexity_over_ceiling "$@"
      ;;
    "") cog::fn::error_raise "MissingArgument" "missing plan-complexity mode" "usage: cog plan-complexity extract|ceiling|over-ceiling" "" "run 'cog plan-complexity --help'" ;;
    *) cog::fn::error_raise "InvalidInput" "unknown plan-complexity mode" "mode: $mode" "" "run 'cog plan-complexity --help'" ;;
  esac
}
