# shellcheck shell=bash
: 'desc: Capture read-only git context for tsk workflows.'

__cog_tsk_snapshot_self_check='.repo_root != "" and (.branch|type=="string") and (.status|type=="object") and (.status.files|type=="array") and (.staged_files|type=="array") and (.unstaged_files|type=="array") and (.diff_stats|type=="object") and .diff_stats.staged.mode == "staged" and .diff_stats.unstaged.mode == "unstaged" and (.recent_log|type=="array")'

__cog_tsk_snapshot_usage() {
  cog::fn::ui_data "Usage: cog tsk-snapshot (<out.json>|--json)"
}

__cog_tsk_snapshot_build_json() {
  local repo_root branch status staged_files unstaged_files staged_stat unstaged_stat recent_log
  repo_root="$(cog::fn::git_root)"
  branch="$(cog::fn::git_current_branch)"
  status="$(cog::fn::git_status_json)"
  staged_files="$(cog::fn::git_staged_files_json)"
  unstaged_files="$(cog::fn::git_unstaged_files_json)"
  staged_stat="$(cog::fn::git_diff_stat_json --staged)"
  unstaged_stat="$(cog::fn::git_diff_stat_json --unstaged)"
  recent_log="$(cog::fn::git_recent_log_json 10)"
  jq -n --arg repo_root "$repo_root" --arg branch "$branch" --argjson status "$status" \
    --argjson staged_files "$staged_files" --argjson unstaged_files "$unstaged_files" \
    --argjson staged_stat "$staged_stat" --argjson unstaged_stat "$unstaged_stat" --argjson recent_log "$recent_log" \
    '{repo_root: $repo_root, branch: $branch, status: $status, staged_files: $staged_files,
      unstaged_files: $unstaged_files, diff_stats: {staged: $staged_stat, unstaged: $unstaged_stat},
      recent_log: $recent_log}'
}

cog::cmd::tsk_snapshot() {
  local mode="" out="" json
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_tsk_snapshot_usage
        return 0
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" "duplicate tsk-snapshot output mode" "" "" "choose either --json or an output path"
        mode=json
        shift
        ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown tsk-snapshot option" "option: $1" "" "run 'cog tsk-snapshot --help'" ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise "TooManyArguments" "too many tsk-snapshot output paths" "argument: $1" "" "run 'cog tsk-snapshot --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done
  [[ -n $mode || ${COG_UI_JSON:-false} == true ]] || cog::fn::error_raise "MissingArgument" "missing tsk-snapshot output mode" "usage: cog tsk-snapshot (<out.json>|--json)" "" "run 'cog tsk-snapshot --help'"
  [[ -n $mode ]] || mode=json
  json="$(__cog_tsk_snapshot_build_json)"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then cog::fn::json_emit "$__cog_tsk_snapshot_self_check" "$json"; else cog::fn::json_write_fragment "$out" "$__cog_tsk_snapshot_self_check" "$json"; fi
}
