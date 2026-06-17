# shellcheck shell=bash
: 'desc: Select the next runnable implementation plan round.'

__cog_queue_select_self_check='(.ok|type=="boolean") and (.queue_path|type=="string") and (.clean_check|type=="boolean") and (.state == "selected" or .state == "complete" or .state == "blocked") and ((.selected == null) or (.selected.item|type=="string")) and (.todo_remaining|type=="array") and (.blocked|type=="array")'

__cog_queue_select_usage() {
  cog::fn::ui_data "Usage: cog queue-select --queue <path> [--repo-root <dir>] [--repo <dir>]... [--no-clean-check] (<out.json>|--json)"
}

__cog_queue_select_result_json() {
  local ok="$1" queue_path="$2" repo_root="$3" clean_check="$4" state="$5" selected="$6" todo="$7" blocked="$8" reason="$9"
  jq -n \
    --argjson ok "$ok" \
    --arg queue_path "$queue_path" \
    --arg repo_root "$repo_root" \
    --argjson clean_check "$clean_check" \
    --arg state "$state" \
    --argjson selected "$selected" \
    --argjson todo_remaining "$todo" \
    --argjson blocked "$blocked" \
    --arg reason "$reason" \
    '{ok: $ok, queue_path: $queue_path, repo_root: $repo_root, clean_check: $clean_check,
      state: $state, selected: $selected, todo_remaining: $todo_remaining, blocked: $blocked,
      reason: (if $ok then null else $reason end)}'
}

__cog_queue_select_build_json() {
  local queue_path="$1" repo_root="$2" clean_check="$3"
  shift 3
  local -a extra_repos=("$@")
  local selected_json dirty state selected todo blocked ok=true reason=""
  cog::fn::queue_validate_rounds_selectable "$queue_path"

  if [[ $clean_check == true ]]; then
    local r
    for r in "$repo_root" "${extra_repos[@]}"; do
      # Bind the clean check to explicit repo roots (not the caller's cwd) so a
      # queue runner cannot start work against a dirty target or satellite repo.
      if ! dirty="$(git -C "$r" status --porcelain=v1 2>/dev/null)"; then
        __cog_queue_select_result_json false "$queue_path" "$repo_root" true blocked null '[]' '[]' "not a verifiable git worktree: $r"
        return 0
      fi
      if [[ -n $dirty ]]; then
        __cog_queue_select_result_json false "$queue_path" "$repo_root" true blocked null '[]' '[]' "dirty worktree: $r"
        return 0
      fi
    done
  fi

  selected_json="$(cog::fn::queue_select_next_round "$queue_path")"
  state="$(jq -r '.state' <<<"$selected_json")"
  selected="$(jq -c '.selected' <<<"$selected_json")"
  todo="$(jq -c '.todo_remaining' <<<"$selected_json")"
  blocked="$(jq -c '.blocked' <<<"$selected_json")"
  if [[ $state == blocked ]]; then
    ok=false
    reason="todo rounds remain but dependencies are not done"
  fi
  __cog_queue_select_result_json "$ok" "$queue_path" "$repo_root" "$clean_check" "$state" "$selected" "$todo" "$blocked" "$reason"
}

cog::cmd::queue_select() {
  local queue_path="" repo_root="" clean_check=true mode="" out="" json
  local -a extra_repos=()
  repo_root="$(pwd -P)"
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_queue_select_usage
        return 0
        ;;
      --queue)
        [[ $# -ge 2 && -z $queue_path ]] || cog::fn::error_raise "MissingArgument" "missing queue path" "option: --queue" "" "run 'cog queue-select --help'"
        queue_path="$2"
        shift 2
        ;;
      --repo-root)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" "missing repo root" "option: --repo-root" "" "run 'cog queue-select --help'"
        repo_root="$2"
        shift 2
        ;;
      --repo)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" "missing repo" "option: --repo" "" "run 'cog queue-select --help'"
        extra_repos+=("$2")
        shift 2
        ;;
      --no-clean-check)
        clean_check=false
        shift
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" "duplicate queue-select output mode" "" "" "choose either --json or an output path"
        mode="json"
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" "unknown queue-select option" "option: $1" "" "run 'cog queue-select --help'"
        ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise "TooManyArguments" "too many queue-select output paths" "argument: $1" "" "run 'cog queue-select --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done

  [[ -n $queue_path && (-n $mode || ${COG_UI_JSON:-false} == true) ]] || cog::fn::error_raise "MissingArgument" \
    "missing queue-select argument" "usage: cog queue-select --queue <path> [--repo-root <dir>] [--no-clean-check] (<out.json>|--json)" "" \
    "run 'cog queue-select --help'"
  [[ -n $mode ]] || mode=json

  json="$(__cog_queue_select_build_json "$queue_path" "$repo_root" "$clean_check" "${extra_repos[@]}")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$__cog_queue_select_self_check" "$json"
  else
    cog::fn::json_write_fragment "$out" "$__cog_queue_select_self_check" "$json"
  fi
  jq -e '.ok == true' <<<"$json" >/dev/null
}
