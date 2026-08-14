# shellcheck shell=bash
: 'desc: Manage operator-approval gate records (approve, check-approval, prune).'

__cog_gate_usage() {
  cog::fn::ui_data "Usage: cog gate approve --gate-id <id> --artifact <file> [--approver <name>] [--notes <text>]"
  cog::fn::ui_data "Usage: cog gate check-approval --gate-id <id> --artifact <file> [--ttl <secs>]"
  cog::fn::ui_data "Usage: cog gate prune-approvals [--older-than <secs>]"
  cog::fn::ui_data "Usage: cog gate --help"
}

__cog_gate_approve_cmd() {
  local gate_id="" artifact_path="" approver="" notes=""
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_gate_usage
        return 0
        ;;
      --gate-id)
        [[ $# -ge 2 && -n ${2:-} && -z $gate_id ]] || cog::fn::error_raise "MissingArgument" \
          "missing gate id" "option: --gate-id" "" "run 'cog gate --help'"
        gate_id="$2"
        shift 2
        ;;
      --artifact)
        [[ $# -ge 2 && -n ${2:-} && -z $artifact_path ]] || cog::fn::error_raise "MissingArgument" \
          "missing artifact path" "option: --artifact" "" "run 'cog gate --help'"
        artifact_path="$2"
        shift 2
        ;;
      --approver)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" \
          "missing approver" "option: --approver" "" "run 'cog gate --help'"
        approver="$2"
        shift 2
        ;;
      --notes)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" \
          "missing notes" "option: --notes" "" "run 'cog gate --help'"
        notes="$2"
        shift 2
        ;;
      -*) cog::fn::error_raise "InvalidInput" \
        "unknown gate approve option" "option: $1" "" "run 'cog gate --help'" ;;
      *) cog::fn::error_raise "TooManyArguments" \
        "too many gate approve arguments" "argument: $1" "" "run 'cog gate --help'" ;;
    esac
  done
  local result
  result="$(cog::fn::gate_approval::write "$gate_id" "$artifact_path" "$approver" "$notes")"
  cog::fn::json_emit '(.ok == true) and (.approval_path | type == "string")' "$result"
}

__cog_gate_check_approval_cmd() {
  local gate_id="" artifact_path="" ttl=""
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_gate_usage
        return 0
        ;;
      --gate-id)
        [[ $# -ge 2 && -n ${2:-} && -z $gate_id ]] || cog::fn::error_raise "MissingArgument" \
          "missing gate id" "option: --gate-id" "" "run 'cog gate --help'"
        gate_id="$2"
        shift 2
        ;;
      --artifact)
        [[ $# -ge 2 && -n ${2:-} && -z $artifact_path ]] || cog::fn::error_raise "MissingArgument" \
          "missing artifact path" "option: --artifact" "" "run 'cog gate --help'"
        artifact_path="$2"
        shift 2
        ;;
      --ttl)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" \
          "missing ttl" "option: --ttl" "" "run 'cog gate --help'"
        ttl="$2"
        shift 2
        ;;
      -*) cog::fn::error_raise "InvalidInput" \
        "unknown gate check-approval option" "option: $1" "" "run 'cog gate --help'" ;;
      *) cog::fn::error_raise "TooManyArguments" \
        "too many gate check-approval arguments" "argument: $1" "" "run 'cog gate --help'" ;;
    esac
  done
  local verdict status=0
  verdict="$(cog::fn::gate_approval::check "$gate_id" "$artifact_path" "$ttl")" || status=$?
  cog::fn::json_emit '(.status | type == "string")' "$verdict"
  return "$status"
}

__cog_gate_prune_approvals_cmd() {
  local older_than=""
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_gate_usage
        return 0
        ;;
      --older-than)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" \
          "missing older-than" "option: --older-than" "" "run 'cog gate --help'"
        older_than="$2"
        shift 2
        ;;
      -*) cog::fn::error_raise "InvalidInput" \
        "unknown gate prune-approvals option" "option: $1" "" "run 'cog gate --help'" ;;
      *) cog::fn::error_raise "TooManyArguments" \
        "too many gate prune-approvals arguments" "argument: $1" "" "run 'cog gate --help'" ;;
    esac
  done
  cog::fn::json_emit '(.ok == true) and (.pruned | type == "array")' \
    "$(cog::fn::gate_approval::prune "$older_than")"
}

cog::cmd::gate() {
  local verb="${1:-}"
  case "$verb" in
    -h | --help | "")
      __cog_gate_usage
      return 0
      ;;
    approve)
      shift
      __cog_gate_approve_cmd "$@"
      ;;
    check-approval)
      shift
      __cog_gate_check_approval_cmd "$@"
      ;;
    prune-approvals)
      shift
      __cog_gate_prune_approvals_cmd "$@"
      ;;
    -*) cog::fn::error_raise "InvalidInput" \
      "unknown gate option" "option: $verb" "" "run 'cog gate --help'" ;;
    *) cog::fn::error_raise "InvalidInput" \
      "unknown gate mode" "mode: $verb" "" \
      "expected approve, check-approval, or prune-approvals" ;;
  esac
}
