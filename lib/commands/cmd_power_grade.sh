# shellcheck shell=bash
: 'desc: Inspect and validate model/effort power grades.'

__cog_power_grade_validate_self_check='(.schema=="cog.power-grade.validate.v1") and (.ok|type=="boolean") and (.matrix_path|type=="string") and (.profile_count|type=="number") and (.named_profile_count|type=="number") and (.errors|type=="array") and (.warnings|type=="array")'
__cog_power_grade_cell_self_check='(.schema=="cog.power-grade.cell.v1") and (.ok|type=="boolean") and (.matrix_path|type=="string") and (.model|type=="string") and (.effort|type=="string") and ((.profile|type=="object") or (.profile == null))'
__cog_power_grade_classify_self_check='(.schema=="cog.power-grade.classify.v1") and (.ok|type=="boolean") and (.matrix_path|type=="string") and (.grade|type=="number") and (.profiles|type=="array")'
__cog_power_grade_compound_self_check='(.schema=="cog.power-grade.compound.v1") and (.ok|type=="boolean") and (.matrix_path|type=="string") and (.input|type=="string") and (.passes|type=="array") and (.base_grade|type=="number") and (.artifact_gain|type=="number") and (.compound_grade|type=="number") and (.errors|type=="array")'
__cog_power_grade_profile_self_check='(.schema=="cog.power-grade.profile.v1") and (.ok|type=="boolean") and (.matrix_path|type=="string") and (.name|type=="string") and ((.claude|type=="object") or (.claude == null)) and ((.codex|type=="object") or (.codex == null))'
__cog_power_grade_skill_tier_self_check='(.schema=="cog.power-grade.skill-tier.v1") and (.ok|type=="boolean") and (.skill|type=="string") and (.file|type=="string") and (.expected|type=="string") and (.actual|type=="string") and (.reason|type=="string")'

__cog_power_grade_usage() {
  cog::fn::ui_data "Usage: cog power-grade validate [--json]"
  cog::fn::ui_data "Usage: cog power-grade cell --model <model> --effort <effort> [--json]"
  cog::fn::ui_data "Usage: cog power-grade classify --grade <n> [--json]"
  cog::fn::ui_data "Usage: cog power-grade compound --passes <profile,profile,...> [--json]"
  cog::fn::ui_data "Usage: cog power-grade profile --name <tier> [--json]"
  cog::fn::ui_data "Usage: cog power-grade skill-tier --skill <name> | --file <path> [--json]"
}

__cog_power_grade_emit_json() {
  local check="$1" json="$2"
  cog::fn::json_emit "$check" "$json"
  jq -e '.ok == true' <<<"$json" >/dev/null || return "$EX_DATAERR"
}

__cog_power_grade_parse_json_flag_only() {
  while (($# > 0)); do
    case "$1" in
      --json)
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown power-grade option" "option: $1" "" "run 'cog power-grade --help'"
        ;;
      *)
        cog::fn::error_raise "InvalidInput" \
          "unexpected power-grade argument" "argument: $1" "" "run 'cog power-grade --help'"
        ;;
    esac
  done
}

__cog_power_grade_validate() {
  local json
  __cog_power_grade_parse_json_flag_only "$@"
  json="$(cog::fn::power_grade::validate_json)"
  __cog_power_grade_emit_json "$__cog_power_grade_validate_self_check" "$json"
}

__cog_power_grade_cell() {
  local model="" effort="" json

  while (($# > 0)); do
    case "$1" in
      --model)
        [[ $# -ge 2 && -n ${2:-} && -z $model ]] || cog::fn::error_raise "MissingArgument" \
          "missing or duplicate power-grade model" "option: --model" "" "run 'cog power-grade --help'"
        model="$2"
        shift 2
        ;;
      --effort)
        [[ $# -ge 2 && -n ${2:-} && -z $effort ]] || cog::fn::error_raise "MissingArgument" \
          "missing or duplicate power-grade effort" "option: --effort" "" "run 'cog power-grade --help'"
        effort="$2"
        shift 2
        ;;
      --json)
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown power-grade cell option" "option: $1" "" "run 'cog power-grade --help'"
        ;;
      *)
        cog::fn::error_raise "InvalidInput" \
          "unexpected power-grade cell argument" "argument: $1" "" "run 'cog power-grade --help'"
        ;;
    esac
  done

  [[ -n $model && -n $effort ]] || cog::fn::error_raise "MissingArgument" \
    "missing power-grade cell argument" "usage: cog power-grade cell --model <model> --effort <effort>" "" \
    "run 'cog power-grade --help'"
  json="$(cog::fn::power_grade::cell_json "$model" "$effort")"
  __cog_power_grade_emit_json "$__cog_power_grade_cell_self_check" "$json"
}

__cog_power_grade_classify() {
  local grade="" json

  while (($# > 0)); do
    case "$1" in
      --grade)
        [[ $# -ge 2 && -n ${2:-} && -z $grade ]] || cog::fn::error_raise "MissingArgument" \
          "missing or duplicate power grade" "option: --grade" "" "run 'cog power-grade --help'"
        grade="$2"
        shift 2
        ;;
      --json)
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown power-grade classify option" "option: $1" "" "run 'cog power-grade --help'"
        ;;
      *)
        cog::fn::error_raise "InvalidInput" \
          "unexpected power-grade classify argument" "argument: $1" "" "run 'cog power-grade --help'"
        ;;
    esac
  done

  [[ -n $grade ]] || cog::fn::error_raise "MissingArgument" \
    "missing power grade" "usage: cog power-grade classify --grade <n>" "" \
    "run 'cog power-grade --help'"
  json="$(cog::fn::power_grade::classify_json "$grade")"
  __cog_power_grade_emit_json "$__cog_power_grade_classify_self_check" "$json"
}

__cog_power_grade_compound() {
  local passes="" json

  while (($# > 0)); do
    case "$1" in
      --passes)
        [[ $# -ge 2 && -n ${2:-} && -z $passes ]] || cog::fn::error_raise "MissingArgument" \
          "missing or duplicate power-grade passes" "option: --passes" "" "run 'cog power-grade --help'"
        passes="$2"
        shift 2
        ;;
      --json)
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown power-grade compound option" "option: $1" "" "run 'cog power-grade --help'"
        ;;
      *)
        cog::fn::error_raise "InvalidInput" \
          "unexpected power-grade compound argument" "argument: $1" "" "run 'cog power-grade --help'"
        ;;
    esac
  done

  [[ -n $passes ]] || cog::fn::error_raise "MissingArgument" \
    "missing power-grade passes" "usage: cog power-grade compound --passes <profile,profile,...>" "" \
    "run 'cog power-grade --help'"
  json="$(cog::fn::power_grade::compound_json "$passes")"
  __cog_power_grade_emit_json "$__cog_power_grade_compound_self_check" "$json"
}

__cog_power_grade_profile() {
  local name="" json

  while (($# > 0)); do
    case "$1" in
      --name)
        [[ $# -ge 2 && -n ${2:-} && -z $name ]] || cog::fn::error_raise "MissingArgument" \
          "missing or duplicate named-profile name" "option: --name" "" "run 'cog power-grade --help'"
        name="$2"
        shift 2
        ;;
      --json)
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown power-grade profile option" "option: $1" "" "run 'cog power-grade --help'"
        ;;
      *)
        cog::fn::error_raise "InvalidInput" \
          "unexpected power-grade profile argument" "argument: $1" "" "run 'cog power-grade --help'"
        ;;
    esac
  done

  [[ -n $name ]] || cog::fn::error_raise "MissingArgument" \
    "missing named-profile name" "usage: cog power-grade profile --name <tier>" "" \
    "run 'cog power-grade --help'"
  json="$(cog::fn::power_grade::profile_json "$name")"
  __cog_power_grade_emit_json "$__cog_power_grade_profile_self_check" "$json"
}

__cog_power_grade_skill_tier() {
  local skill="" file="" json

  while (($# > 0)); do
    case "$1" in
      --skill)
        [[ $# -ge 2 && -n ${2:-} && -z $skill ]] || cog::fn::error_raise "MissingArgument" \
          "missing or duplicate skill name" "option: --skill" "" "run 'cog power-grade --help'"
        skill="$2"
        shift 2
        ;;
      --file)
        [[ $# -ge 2 && -n ${2:-} && -z $file ]] || cog::fn::error_raise "MissingArgument" \
          "missing or duplicate skill file" "option: --file" "" "run 'cog power-grade --help'"
        file="$2"
        shift 2
        ;;
      --json)
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown power-grade skill-tier option" "option: $1" "" "run 'cog power-grade --help'"
        ;;
      *)
        cog::fn::error_raise "InvalidInput" \
          "unexpected power-grade skill-tier argument" "argument: $1" "" "run 'cog power-grade --help'"
        ;;
    esac
  done

  [[ -n $skill || -n $file ]] || cog::fn::error_raise "MissingArgument" \
    "missing skill identifier" "usage: cog power-grade skill-tier --skill <name> | --file <path>" "" \
    "run 'cog power-grade --help'"
  json="$(cog::fn::power_grade::skill_tier_json "$skill" "$file")"
  __cog_power_grade_emit_json "$__cog_power_grade_skill_tier_self_check" "$json"
}

cog::cmd::power_grade() {
  local sub="${1:-}"

  case "$sub" in
    -h | --help)
      __cog_power_grade_usage
      ;;
    validate)
      shift
      __cog_power_grade_validate "$@"
      ;;
    cell)
      shift
      __cog_power_grade_cell "$@"
      ;;
    classify)
      shift
      __cog_power_grade_classify "$@"
      ;;
    compound)
      shift
      __cog_power_grade_compound "$@"
      ;;
    profile)
      shift
      __cog_power_grade_profile "$@"
      ;;
    skill-tier)
      shift
      __cog_power_grade_skill_tier "$@"
      ;;
    "")
      cog::fn::error_raise "MissingArgument" \
        "missing power-grade subcommand" "usage: cog power-grade validate|cell|classify|compound|profile|skill-tier" "" \
        "run 'cog power-grade --help'"
      ;;
    *)
      cog::fn::error_raise "InvalidInput" \
        "unknown power-grade subcommand" "subcommand: ${sub}" "" \
        "run 'cog power-grade --help'"
      ;;
  esac
}
