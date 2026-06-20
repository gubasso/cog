# shellcheck shell=bash
: 'desc: Resolve a selected main queue plan entry to its executable form.'

__cog_runner_queue_resolve_plan_self_check='(.ok == true) and (.item|type=="string") and (.kind == "inner_queue") and (.repo_root|type=="string") and (.main_queue_path|type=="string") and (.target_path|type=="string") and (.inner_queue_path|type=="string") and (.prompt|type=="string") and (.repos|type=="array")'

__cog_runner_queue_resolve_plan_usage() {
  cog::fn::ui_data "Usage: cog runner-queue-resolve-plan --repo-root <dir> --queue <main-queue> --item <item> (<out.json>|--json)"
}

__cog_runner_queue_resolve_plan_strip_trailing_slashes() {
  local path="$1"
  while [[ $path != "/" && $path == */ ]]; do
    path="${path%/}"
  done
  printf '%s\n' "$path"
}

__cog_runner_queue_resolve_plan_entry_json() {
  local queue_path="$1" item="$2"
  ITEM="$item" yq e -o=json '.plans[]? | select(.item == strenv(ITEM))' "$queue_path" | jq -s .
}

__cog_runner_queue_resolve_plan_build_json() {
  local repo_root="$1" queue_path="$2" item="$3"
  local entries_json entry_count entry_json prompt target target_path inner_queue_path repos_json

  [[ -n $repo_root && -n $queue_path && -n $item ]] || cog::fn::error_raise_with_exit 2 "MissingArgument" \
    "missing resolve-plan argument" "usage: cog runner-queue-resolve-plan --repo-root <dir> --queue <main-queue> --item <item>" "" \
    "run 'cog runner-queue-resolve-plan --help'"
  [[ -d $repo_root ]] || cog::fn::error_raise "InputNotFound" \
    "repo root not found" "path: ${repo_root}" "" "check --repo-root"

  cog::fn::queue_validate_file "$queue_path" plans
  entries_json="$(__cog_runner_queue_resolve_plan_entry_json "$queue_path" "$item")"
  entry_count="$(jq 'length' <<<"$entries_json")"
  case "$entry_count" in
    0)
      cog::fn::error_raise "InvalidInput" "main queue item not found" "item: ${item}" "path: ${queue_path}" ""
      ;;
    1)
      entry_json="$(jq -c '.[0]' <<<"$entries_json")"
      ;;
    *)
      cog::fn::error_raise "InvalidInput" "duplicate main queue item" "item: ${item}" "path: ${queue_path}" "remove duplicate items"
      ;;
  esac

  prompt="$(jq -r '.prompt' <<<"$entry_json")"
  if [[ $prompt =~ ^/(prex|executor-prex|executor-claude|executor-codex-session)[[:space:]]+-ar[[:space:]]+(@?[^[:space:]]+)[[:space:]]*$ ]]; then
    target="${BASH_REMATCH[2]}"
  else
    cog::fn::error_raise "InvalidInput" \
      "unsupported plan prompt" "item: ${item}" "prompt: ${prompt}" "expected /prex, /executor-prex, /executor-claude, or /executor-codex-session -ar [@]<target>"
  fi
  [[ $target == @* ]] && target="${target#@}"
  target="$(__cog_runner_queue_resolve_plan_strip_trailing_slashes "$target")"
  if [[ $target == /* ]]; then
    target_path="$target"
  else
    target_path="${repo_root%/}/${target}"
  fi
  target_path="$(__cog_runner_queue_resolve_plan_strip_trailing_slashes "$target_path")"

  [[ -e $target_path ]] || cog::fn::error_raise "InvalidInput" \
    "plan target not found" "path: ${target_path}" "item: ${item}" ""
  [[ -d $target_path ]] || cog::fn::error_raise "InvalidInput" \
    "plan target is not a directory" "path: ${target_path}" "item: ${item}" ""

  # Plan directories are always flat siblings directly under .implementation-plans/plans/.
  # Fail closed on any nested plan in the canonical tree (it would be invisible to review-implementation-plans).
  cog::fn::review_implementation_plans_assert_flat "$repo_root"

  inner_queue_path="${target_path}/queue-rounds.yaml"
  [[ -f $inner_queue_path ]] || cog::fn::error_raise "InvalidInput" \
    "plan target has no queue-rounds.yaml" "path: ${target_path}" "item: ${item}" ""

  cog::fn::queue_validate_file "$inner_queue_path" rounds
  repos_json="$(yq e -o=json '.repos // []' "$inner_queue_path")"

  jq -n \
    --argjson ok true \
    --arg item "$item" \
    --arg kind "inner_queue" \
    --arg repo_root "$repo_root" \
    --arg main_queue_path "$queue_path" \
    --arg target_path "$target_path" \
    --arg inner_queue_path "$inner_queue_path" \
    --arg prompt "$prompt" \
    --argjson repos "$repos_json" \
    '{ok: $ok, item: $item, kind: $kind, repo_root: $repo_root, main_queue_path: $main_queue_path,
      target_path: $target_path, inner_queue_path: $inner_queue_path, prompt: $prompt, repos: $repos}'
}

cog::cmd::runner_queue_resolve_plan() {
  local repo_root="" queue_path="" item="" mode="" out="" json
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_runner_queue_resolve_plan_usage
        return 0
        ;;
      --repo-root)
        [[ $# -ge 2 && -z $repo_root ]] || cog::fn::error_raise_with_exit 2 "MissingArgument" "missing repo root" "option: --repo-root" "" "run 'cog runner-queue-resolve-plan --help'"
        repo_root="$2"
        shift 2
        ;;
      --queue)
        [[ $# -ge 2 && -z $queue_path ]] || cog::fn::error_raise_with_exit 2 "MissingArgument" "missing main queue" "option: --queue" "" "run 'cog runner-queue-resolve-plan --help'"
        queue_path="$2"
        shift 2
        ;;
      --item)
        [[ $# -ge 2 && -z $item ]] || cog::fn::error_raise_with_exit 2 "MissingArgument" "missing queue item" "option: --item" "" "run 'cog runner-queue-resolve-plan --help'"
        item="$2"
        shift 2
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise_with_exit 2 "InvalidInput" "duplicate resolve-plan output mode" "" "" "choose either --json or an output path"
        mode="json"
        shift
        ;;
      -*)
        cog::fn::error_raise_with_exit 2 "InvalidInput" "unknown resolve-plan option" "option: $1" "" "run 'cog runner-queue-resolve-plan --help'"
        ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise_with_exit 2 "TooManyArguments" "too many resolve-plan output paths" "argument: $1" "" "run 'cog runner-queue-resolve-plan --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done

  [[ -n $mode || ${COG_UI_JSON:-false} == true ]] || cog::fn::error_raise_with_exit 2 "MissingArgument" \
    "missing resolve-plan output mode" "usage: cog runner-queue-resolve-plan ... (<out.json>|--json)" "" \
    "run 'cog runner-queue-resolve-plan --help'"
  [[ -n $mode ]] || mode=json
  json="$(__cog_runner_queue_resolve_plan_build_json "$repo_root" "$queue_path" "$item")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$__cog_runner_queue_resolve_plan_self_check" "$json"
  else
    cog::fn::json_write_fragment "$out" "$__cog_runner_queue_resolve_plan_self_check" "$json"
  fi
}
