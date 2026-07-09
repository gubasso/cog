# shellcheck shell=bash
: 'desc: Resolve and check the repo git identity (user.name/user.email).'

__cog_git_identity_self_check='(.ok|type=="boolean") and has("name") and has("email")'

__cog_git_identity_usage() {
  cog::fn::ui_data "Usage: cog git-identity check [--project-root <dir>] (<out.json>|--json)"
}

# Resolve the repo git identity and emit it. Fails closed: exits non-zero when the
# identity is not fully configured (.ok == false), so a caller can gate on the exit
# status and pause for remediation.
__cog_git_identity_check() {
  local project_root out="" mode="" json
  project_root="$(pwd -P)"
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_git_identity_usage
        return 0
        ;;
      --project-root)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing project root" "option: --project-root" "" "run 'cog git-identity --help'"
        project_root="$2"
        shift 2
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" "duplicate git-identity output mode" "" "" "choose either --json or an output path"
        mode=json
        shift
        ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown git-identity option" "option: $1" "" "run 'cog git-identity --help'" ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise "TooManyArguments" "too many git-identity output paths" "argument: $1" "" "run 'cog git-identity --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done
  [[ -n $mode || ${COG_UI_JSON:-false} == true ]] || cog::fn::error_raise "MissingArgument" "missing git-identity output mode" "usage: cog git-identity check [--project-root <dir>] (<out.json>|--json)" "" "run 'cog git-identity --help'"
  [[ -n $mode ]] || mode=json
  json="$(cog::fn::git_identity_json "$project_root")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then cog::fn::json_emit "$__cog_git_identity_self_check" "$json"; else cog::fn::json_write_fragment "$out" "$__cog_git_identity_self_check" "$json"; fi
  jq -e '.ok == true' <<<"$json" >/dev/null
}

cog::cmd::git_identity() {
  local verb="${1:-}"
  case "$verb" in
    -h | --help | "")
      __cog_git_identity_usage
      return 0
      ;;
    check)
      shift
      __cog_git_identity_check "$@"
      ;;
    *) cog::fn::error_raise "InvalidInput" "unknown git-identity verb" "verb: $verb" "" "run 'cog git-identity --help'" ;;
  esac
}
