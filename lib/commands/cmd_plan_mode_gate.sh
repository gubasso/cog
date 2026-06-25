# shellcheck shell=bash
: 'desc: Render the canonical plan-mode gate stanza.'

__cog_plan_mode_gate_usage() {
  cog::fn::ui_data "Usage: cog plan-mode-gate render --skill <name>"
}

__cog_plan_mode_gate_render() {
  local name=""

  while (($# > 0)); do
    case "$1" in
      --skill)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" \
          "missing plan-mode-gate skill name" "option: --skill" "" "run 'cog plan-mode-gate --help'"
        name="$2"
        shift 2
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown plan-mode-gate render option" "option: $1" "" "run 'cog plan-mode-gate --help'"
        ;;
      *)
        cog::fn::error_raise "InvalidInput" \
          "too many plan-mode-gate render arguments" "argument: $1" "" "run 'cog plan-mode-gate --help'"
        ;;
    esac
  done

  [[ -n $name ]] || cog::fn::error_raise "MissingArgument" \
    "missing plan-mode-gate skill name" "option: --skill" "" "run 'cog plan-mode-gate --help'"
  cog::fn::skill::name_is_valid "$name" || cog::fn::error_raise "InvalidInput" \
    "invalid skill name" "name: ${name}" "" "use ^[a-z0-9-]{1,64}$ and avoid reserved names anthropic and claude"

  cog::fn::skill::plan_mode_gate_render "$name"
}

cog::cmd::plan_mode_gate() {
  local mode="${1:-}"

  case "$mode" in
    -h | --help)
      __cog_plan_mode_gate_usage
      ;;
    render)
      shift
      __cog_plan_mode_gate_render "$@"
      ;;
    "")
      cog::fn::error_raise "MissingArgument" \
        "missing plan-mode-gate mode" "usage: cog plan-mode-gate render" "" "run 'cog plan-mode-gate --help'"
      ;;
    *)
      cog::fn::error_raise "InvalidInput" \
        "unknown plan-mode-gate mode" "mode: ${mode}" "" "run 'cog plan-mode-gate --help'"
      ;;
  esac
}
