# shellcheck shell=bash
: 'desc: Emit uniform machine status lines and human messages.'

__cog_msg_ctx() {
  local c="${1//[^a-zA-Z0-9]/_}"
  cog::fn::ui_dataf '%s' "${c^^}"
}

__cog_msg_usage() {
  cog::fn::ui_data "Usage: cog msg <kind> [args]"
  cog::fn::ui_data ""
  cog::fn::ui_data "Kinds:"
  cog::fn::ui_data "  resolved <path>"
  cog::fn::ui_data "  ok <context> [detail...]"
  cog::fn::ui_data "  failed <context> <reason...>"
  cog::fn::ui_data "  kv <KEY> <value>"
  cog::fn::ui_data "  stage <text...>"
  cog::fn::ui_data "  info <text...>"
  cog::fn::ui_data "  warn <text...>"
  cog::fn::ui_data "  error <context> <text...>"
  cog::fn::ui_data "  fatal <context> <text...>"
}

__cog_msg_require_arg() {
  local value="${1:-}"
  local usage="$2"

  [[ -n $value ]] || cog::fn::error_raise "MissingArgument" \
    "missing required argument" "usage: ${usage}" "" "run 'cog msg --help'"
}

cog::cmd::msg() {
  local kind="${1:-}"
  local ctx

  case "$kind" in
    -h | --help)
      __cog_msg_usage
      return 0
      ;;
    "")
      cog::fn::error_raise "BadMsgKind" \
        "missing msg kind" "" "" "run 'cog msg --help'"
      ;;
  esac
  shift

  case "$kind" in
    resolved)
      __cog_msg_require_arg "${1:-}" "cog msg resolved <path>"
      cog::fn::ui_data "RESOLVED $1"
      ;;
    ok)
      __cog_msg_require_arg "${1:-}" "cog msg ok <context> [detail...]"
      ctx="$(__cog_msg_ctx "$1")"
      shift
      if (($# > 0)); then
        cog::fn::ui_data "${ctx}_OK $*"
      else
        cog::fn::ui_data "${ctx}_OK"
      fi
      ;;
    failed)
      __cog_msg_require_arg "${1:-}" "cog msg failed <context> <reason...>"
      ctx="$(__cog_msg_ctx "$1")"
      shift
      __cog_msg_require_arg "${1:-}" "cog msg failed <context> <reason...>"
      cog::fn::ui_data "${ctx}_FAILED $*"
      ;;
    kv)
      __cog_msg_require_arg "${1:-}" "cog msg kv <KEY> <value>"
      __cog_msg_require_arg "${2:-}" "cog msg kv <KEY> <value>"
      cog::fn::ui_data "${1}=${2}"
      ;;
    stage)
      __cog_msg_require_arg "${1:-}" "cog msg stage <text...>"
      cog::fn::ui_human "▶ $*"
      ;;
    info)
      __cog_msg_require_arg "${1:-}" "cog msg info <text...>"
      cog::fn::ui_human "$*"
      ;;
    warn)
      __cog_msg_require_arg "${1:-}" "cog msg warn <text...>"
      cog::fn::ui_warn "$*"
      ;;
    error)
      __cog_msg_require_arg "${1:-}" "cog msg error <context> <text...>"
      local error_ctx="$1"
      shift
      __cog_msg_require_arg "${1:-}" "cog msg error <context> <text...>"
      cog::fn::ui_human "❌ ${error_ctx}: $*"
      ;;
    fatal)
      __cog_msg_require_arg "${1:-}" "cog msg fatal <context> <text...>"
      local fatal_ctx="$1"
      shift
      __cog_msg_require_arg "${1:-}" "cog msg fatal <context> <text...>"
      cog::fn::ui_human "❌ ${fatal_ctx}: $*"
      exit "$EX_SOFTWARE"
      ;;
    *)
      cog::fn::error_raise "BadMsgKind" \
        "unknown msg kind" "kind: ${kind}" "" "run 'cog msg --help'"
      ;;
  esac
}
