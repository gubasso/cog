# shellcheck shell=bash
: 'desc: Detect changed-file review scope.'

__cog_review_scope_self_check='.repo_root != null and (.changed_files | type == "array") and (.staged_files | type == "array") and (.unstaged_files | type == "array") and (.status_files | type == "array") and (.diff_stats | type == "object")'

__cog_review_scope_usage() {
  cog::fn::ui_data "Usage: cog review-scope (<out.json>|--json)"
}

__cog_review_scope_changed_files() {
  local staged="$1"
  local unstaged="$2"
  local status_files="$3"
  jq -cn \
    --argjson staged "$staged" \
    --argjson unstaged "$unstaged" \
    --argjson status_files "$status_files" \
    '($staged + $unstaged + ($status_files | map(select(.untracked) | .path))) | unique'
}

__cog_review_scope_build_json() {
  local repo_root branch staged_files unstaged_files status_json status_files staged_stat unstaged_stat changed_files
  repo_root="$(cog::fn::git_root)" || cog::fn::error_raise "InputNotFound" \
    "could not resolve git repository root" "command: git rev-parse --show-toplevel" "" \
    "run from inside a git work tree"
  branch="$(cog::fn::git_current_branch)"
  staged_files="$(cog::fn::git_staged_files_json)"
  unstaged_files="$(cog::fn::git_unstaged_files_json)"
  status_json="$(cog::fn::git_status_json)"
  status_files="$(jq -c '.files' <<<"$status_json")"
  staged_stat="$(cog::fn::git_diff_stat_json --staged)"
  unstaged_stat="$(cog::fn::git_diff_stat_json --unstaged)"
  changed_files="$(__cog_review_scope_changed_files "$staged_files" "$unstaged_files" "$status_files")"

  jq -n \
    --arg repo_root "$repo_root" \
    --arg branch "$branch" \
    --argjson changed_files "$changed_files" \
    --argjson staged_files "$staged_files" \
    --argjson unstaged_files "$unstaged_files" \
    --argjson status_files "$status_files" \
    --argjson staged_stat "$staged_stat" \
    --argjson unstaged_stat "$unstaged_stat" \
    '{
      repo_root: $repo_root,
      branch: $branch,
      changed_files: $changed_files,
      staged_files: $staged_files,
      unstaged_files: $unstaged_files,
      status_files: $status_files,
      diff_stats: {
        staged: $staged_stat,
        unstaged: $unstaged_stat
      }
    }'
}

cog::cmd::review_scope() {
  local mode="" out="" json

  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_review_scope_usage
        return 0
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" \
          "duplicate review-scope output mode" "" "" "choose either --json or an output path"
        mode=json
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown review-scope option" "option: $1" "" "run 'cog review-scope --help'"
        ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise "TooManyArguments" \
          "too many review-scope output paths" "argument: $1" "" "run 'cog review-scope --help'"
        out="$1"
        mode=file
        shift
        ;;
    esac
  done

  [[ -n $mode || ${COG_UI_JSON:-false} != true ]] || mode=json
  [[ -n $mode ]] || cog::fn::error_raise "MissingArgument" \
    "missing review-scope output mode" "usage: cog review-scope (<out.json>|--json)" "" \
    "run 'cog review-scope --help'"

  json="$(__cog_review_scope_build_json)"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$__cog_review_scope_self_check" "$json"
  else
    cog::fn::json_write_fragment "$out" "$__cog_review_scope_self_check" "$json"
  fi
}
