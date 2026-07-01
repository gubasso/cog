# shellcheck shell=bash
: 'desc: Show and check core skill-class contracts and prerequisites.'

__cog_skill_class_list_self_check='(.schema=="cog.skill-class.list.v1") and (.ok==true) and (.classes|type=="array")'
__cog_skill_class_show_self_check='(.schema=="cog.skill-class.show.v1") and (.ok==true) and (.class|type=="string") and (.contract|type=="object")'
__cog_skill_class_check_self_check='(.schema=="cog.skill-class.check.v1") and (.ok|type=="boolean") and (.class|type=="string") and (.missing|type=="array") and (.forbidden_present|type=="array")'

__cog_skill_class_usage() {
  cog::fn::ui_data "Usage: cog skill-class list [--json]"
  cog::fn::ui_data "Usage: cog skill-class show --class <plan|review|review-plan|executor|runner> [--json]"
  cog::fn::ui_data "Usage: cog skill-class check --skill <path> [--json]"
}

__cog_skill_class_list() {
  while (($# > 0)); do
    case "$1" in
      --json) shift ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown skill-class list option" "option: $1" "" "run 'cog skill-class --help'" ;;
      *) cog::fn::error_raise "InvalidInput" "unexpected skill-class list argument" "argument: $1" "" "run 'cog skill-class --help'" ;;
    esac
  done
  cog::fn::json_emit "$__cog_skill_class_list_self_check" "$(cog::fn::skill_class::list_json)"
}

__cog_skill_class_show() {
  local class="" json
  while (($# > 0)); do
    case "$1" in
      --class)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" "missing class" "option: --class" "" "run 'cog skill-class --help'"
        class="$2"
        shift 2
        ;;
      --json) shift ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown skill-class show option" "option: $1" "" "run 'cog skill-class --help'" ;;
      *) cog::fn::error_raise "InvalidInput" "unexpected skill-class show argument" "argument: $1" "" "run 'cog skill-class --help'" ;;
    esac
  done
  [[ -n $class ]] || cog::fn::error_raise "MissingArgument" "missing class" "usage: cog skill-class show --class <c> --json" "" "run 'cog skill-class --help'"
  json="$(cog::fn::skill_class::show_json "$class")"
  cog::fn::json_emit "$__cog_skill_class_show_self_check" "$json"
}

__cog_skill_class_check() {
  local skill="" json
  while (($# > 0)); do
    case "$1" in
      --skill)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" "missing skill path" "option: --skill" "" "run 'cog skill-class --help'"
        skill="$2"
        shift 2
        ;;
      --json) shift ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown skill-class check option" "option: $1" "" "run 'cog skill-class --help'" ;;
      *)
        [[ -z $skill ]] || cog::fn::error_raise "InvalidInput" "unexpected skill-class check argument" "argument: $1" "" "run 'cog skill-class --help'"
        skill="$1"
        shift
        ;;
    esac
  done
  [[ -n $skill ]] || cog::fn::error_raise "MissingArgument" "missing skill path" "usage: cog skill-class check --skill <path> --json" "" "run 'cog skill-class --help'"
  json="$(cog::fn::skill_class::check_json "$skill")"
  cog::fn::json_emit "$__cog_skill_class_check_self_check" "$json"
  jq -e '.ok == true' <<<"$json" >/dev/null || return "$EX_DATAERR"
}

cog::cmd::skill_class() {
  local mode="${1:-}"
  case "$mode" in
    -h | --help) __cog_skill_class_usage ;;
    list)
      shift
      __cog_skill_class_list "$@"
      ;;
    show)
      shift
      __cog_skill_class_show "$@"
      ;;
    check)
      shift
      __cog_skill_class_check "$@"
      ;;
    "") cog::fn::error_raise "MissingArgument" "missing skill-class mode" "usage: cog skill-class list|show|check" "" "run 'cog skill-class --help'" ;;
    *) cog::fn::error_raise "InvalidInput" "unknown skill-class mode" "mode: $mode" "" "run 'cog skill-class --help'" ;;
  esac
}
