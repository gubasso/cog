# shellcheck shell=bash
: 'desc: Validate a commit message against Conventional Commits (or defer to the repo linter).'

__cog_gc_commit_lint_self_check='.ok != null and (.deferred | type == "boolean") and (.violations | type == "array")'

__cog_gc_commit_lint_usage() {
  cog::fn::ui_data "Usage: cog gc-commit-lint --message-file <file> [--repo-root <dir>] (<out.json>|--json)"
}

cog::cmd::gc_commit_lint() {
  local message_file="" repo_root_flag="" mode="" out="" json

  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_gc_commit_lint_usage
        return 0
        ;;
      --message-file)
        [[ $# -ge 2 && -n ${2:-} && -z $message_file ]] || cog::fn::error_raise "MissingArgument" \
          "missing message file" "option: --message-file" "" "run 'cog gc-commit-lint --help'"
        message_file="$2"
        shift 2
        ;;
      --repo-root)
        [[ $# -ge 2 && -n ${2:-} && -z $repo_root_flag ]] || cog::fn::error_raise "MissingArgument" \
          "missing repo root" "option: --repo-root" "" "run 'cog gc-commit-lint --help'"
        repo_root_flag="$2"
        shift 2
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" \
          "duplicate gc-commit-lint output mode" "" "" "choose either --json or an output path"
        mode="json"
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown gc-commit-lint option" "option: $1" "" "run 'cog gc-commit-lint --help'"
        ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise "TooManyArguments" \
          "too many gc-commit-lint output paths" "argument: $1" "" "run 'cog gc-commit-lint --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done

  [[ -n $mode || ${COG_UI_JSON:-false} != true ]] || mode=json
  [[ -n $message_file && -n $mode ]] || cog::fn::error_raise "MissingArgument" \
    "missing gc-commit-lint argument" "usage: cog gc-commit-lint --message-file <file> (<out.json>|--json)" "" \
    "run 'cog gc-commit-lint --help'"

  json="$(cog::fn::git_commit_msg_lint "$message_file" "$repo_root_flag")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$__cog_gc_commit_lint_self_check" "$json"
  else
    cog::fn::json_write_fragment "$out" "$__cog_gc_commit_lint_self_check" "$json"
  fi
  jq -e '.ok == true' <<<"$json" >/dev/null
}
