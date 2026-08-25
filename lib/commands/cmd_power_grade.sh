# shellcheck shell=bash
: 'desc: Inspect and validate model/effort power grades.'

__cog_power_grade_tier_self_check='(.schema=="cog.power-grade.tier.v1") and (.ok|type=="boolean") and (.matrix_path|type=="string") and (.name|type=="string") and ((.claude|type=="object") or (.claude == null)) and ((.codex|type=="object") or (.codex == null))'
__cog_power_grade_skill_tier_self_check='(.schema=="cog.power-grade.skill-tier.v1") and (.ok|type=="boolean") and (.skill|type=="string") and (.file|type=="string") and (.expected|type=="string") and (.actual|type=="string") and (.reason|type=="string")'

__cog_power_grade_usage() {
  cog::fn::ui_data "Usage: cog power-grade tier --name <name> [--json]"
  cog::fn::ui_data "Usage: cog power-grade skill-tier --skill <name> | --file <path> [--json]"
}

__cog_power_grade_emit_json() {
  local check="$1" json="$2"
  cog::fn::json_emit "$check" "$json"
  jq -e '.ok == true' <<<"$json" >/dev/null || return "$EX_DATAERR"
}

__cog_power_grade_tier() {
  local name="" json

  while (($# > 0)); do
    case "$1" in
      --name)
        [[ $# -ge 2 && -n ${2:-} && -z $name ]] || cog::fn::error_raise "MissingArgument" \
          "missing or duplicate tier name" "option: --name" "" "run 'cog power-grade --help'"
        name="$2"
        shift 2
        ;;
      --json)
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown power-grade tier option" "option: $1" "" "run 'cog power-grade --help'"
        ;;
      *)
        cog::fn::error_raise "InvalidInput" \
          "unexpected power-grade tier argument" "argument: $1" "" "run 'cog power-grade --help'"
        ;;
    esac
  done

  [[ -n $name ]] || cog::fn::error_raise "MissingArgument" \
    "missing tier name" "usage: cog power-grade tier --name <name>" "" \
    "run 'cog power-grade --help'"
  json="$(cog::fn::power_grade::tier_json "$name")"
  __cog_power_grade_emit_json "$__cog_power_grade_tier_self_check" "$json"
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
    tier)
      shift
      __cog_power_grade_tier "$@"
      ;;
    skill-tier)
      shift
      __cog_power_grade_skill_tier "$@"
      ;;
    "")
      cog::fn::error_raise "MissingArgument" \
        "missing power-grade subcommand" "usage: cog power-grade validate|cell|classify|compound|tier|skill-tier" "" \
        "run 'cog power-grade --help'"
      ;;
    *)
      cog::fn::error_raise "InvalidInput" \
        "unknown power-grade subcommand" "subcommand: ${sub}" "" \
        "run 'cog power-grade --help'"
      ;;
  esac
}
