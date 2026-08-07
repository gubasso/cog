# shellcheck shell=bash
: 'desc: Reconcile and stage explicit session files.'

__cog_gc_stage_self_check='.ok != null and (.session_files | type == "array") and (.final_staged | type == "array") and (.restaged | type == "array")'

__cog_gc_stage_usage() {
  cog::fn::ui_data "Usage: cog gc-stage --session-files <file> [--repo-root <dir>] (<out.json>|--json)"
}

__cog_gc_stage_append_unique() {
  local out_name="$1"
  shift
  local -n __append_ref="$out_name"
  local item
  for item in "$@"; do
    [[ -n $item ]] || continue
    cog::fn::git_str_in_args "$item" "${__append_ref[@]}" || __append_ref+=("$item")
  done
}

# Expand session paths into the literal file paths git can carry in its index.
# A bare directory never appears in `git diff --staged --name-only`, so leaving
# it unexpanded makes the equality check below report a permanent false
# mismatch. Expansion resolves a directory to the paths under it that are
# already staged, dirty in the worktree, or untracked; a directory with no such
# content contributes nothing and simply drops out.
__cog_gc_stage_expand_session_files() {
  local out_name="$1"
  local root="$2"
  shift 2
  local -n __expand_ref="$out_name"
  local -a git_c=("$@")
  local path
  local -a expanded=()

  for path in "${__expand_ref[@]}"; do
    if [[ -d ${root}/${path} ]]; then
      local -a from_dir=()
      mapfile -t from_dir < <(
        git "${git_c[@]}" diff --staged --no-renames --name-only -- "$path"
        git "${git_c[@]}" diff --no-renames --name-only -- "$path"
        git "${git_c[@]}" ls-files --others --exclude-standard -- "$path"
      )
      __cog_gc_stage_append_unique expanded "${from_dir[@]}"
    else
      __cog_gc_stage_append_unique expanded "$path"
    fi
  done
  __expand_ref=("${expanded[@]}")
}

__cog_gc_stage_command_object() {
  local action="$1"
  local path="$2"
  jq -cn --arg action "$action" --arg path "$path" '{action: $action, path: $path}'
}

__cog_gc_stage_build_json() {
  local session_file="$1"
  local repo_root_flag="${2:-}"
  local root staged_path session_path final_path ok=true reason=""
  local -a git_c=()
  local -a requested=() session_files=() initial_staged=() final_staged=() dirty=()
  local -a unstaged=() staged=() restaged=() mismatch=() commands=()

  if [[ -n $repo_root_flag ]]; then
    root="$(cog::fn::git_root_for "$repo_root_flag")" || cog::fn::error_raise "InvalidInput" \
      "gc-stage: not a git worktree" "path: ${repo_root_flag}" "" "pass a git worktree root"
    git_c=(-C "$root")
  else
    root="$(cog::fn::git_root)"
  fi
  cog::fn::git_read_session_files requested "$session_file" relative
  session_files=("${requested[@]}")
  __cog_gc_stage_expand_session_files session_files "$root" "${git_c[@]}"
  # The worktree-dirty set: tracked paths with unstaged edits or deletions, plus
  # untracked files. A path in this set must be re-added even when it already
  # appears in the staged set, or its later worktree edits silently miss the
  # commit. A staged rename is the canonical case: both raw paths are already
  # staged, so an index-only check would skip the edits made after the rename.
  mapfile -t dirty < <(
    git "${git_c[@]}" diff --no-renames --name-only
    git "${git_c[@]}" ls-files --others --exclude-standard
  )
  # --no-renames: report a staged rename as its raw delete+add path pair, not a
  # single rename-detected destination. The session-files contract lists every
  # literal path touched (old and new), so the staged set must be the raw path
  # set for the equality check below to hold. Without it, git collapses a
  # rename to one destination line and a rename-heavy commit fails closed.
  mapfile -t initial_staged < <(git "${git_c[@]}" diff --staged --no-renames --name-only)

  for staged_path in "${initial_staged[@]}"; do
    if ! cog::fn::git_str_in_args "$staged_path" "${session_files[@]}"; then
      if git "${git_c[@]}" reset HEAD -- "$staged_path" >/dev/null; then
        unstaged+=("$staged_path")
        commands+=("$(__cog_gc_stage_command_object unstage "$staged_path")")
      fi
    fi
  done

  mapfile -t final_staged < <(git "${git_c[@]}" diff --staged --no-renames --name-only)
  # Stage a session path when it is missing from the index, and re-stage it when
  # it still carries worktree changes. Never blanket-add: a staged rename's old
  # path is gone from both the worktree and the index, and `git add` on it fails
  # with "pathspec did not match any files".
  for session_path in "${session_files[@]}"; do
    if ! cog::fn::git_str_in_args "$session_path" "${final_staged[@]}"; then
      if git "${git_c[@]}" add -- "$session_path"; then
        staged+=("$session_path")
        commands+=("$(__cog_gc_stage_command_object stage "$session_path")")
      fi
    elif cog::fn::git_str_in_args "$session_path" "${dirty[@]}"; then
      if git "${git_c[@]}" add -- "$session_path"; then
        restaged+=("$session_path")
        commands+=("$(__cog_gc_stage_command_object restage "$session_path")")
      fi
    fi
  done

  mapfile -t final_staged < <(git "${git_c[@]}" diff --staged --no-renames --name-only)
  for final_path in "${final_staged[@]}"; do
    cog::fn::git_str_in_args "$final_path" "${session_files[@]}" || mismatch+=("$final_path")
  done
  for session_path in "${session_files[@]}"; do
    cog::fn::git_str_in_args "$session_path" "${final_staged[@]}" || mismatch+=("$session_path")
  done

  if ((${#session_files[@]} == 0)); then
    ok=false
    reason="no session path resolved to stageable content"
  elif ((${#mismatch[@]} > 0 || ${#final_staged[@]} != ${#session_files[@]})); then
    ok=false
    reason="final staged set differs from session files"
  fi

  jq -n \
    --argjson ok "$ok" \
    --arg repo_root "$root" \
    --argjson requested "$(cog::fn::git_json_array_from_lines "${requested[@]}")" \
    --argjson session_files "$(cog::fn::git_json_array_from_lines "${session_files[@]}")" \
    --argjson initial_staged "$(cog::fn::git_json_array_from_lines "${initial_staged[@]}")" \
    --argjson unstaged "$(cog::fn::git_json_array_from_lines "${unstaged[@]}")" \
    --argjson staged "$(cog::fn::git_json_array_from_lines "${staged[@]}")" \
    --argjson restaged "$(cog::fn::git_json_array_from_lines "${restaged[@]}")" \
    --argjson final_staged "$(cog::fn::git_json_array_from_lines "${final_staged[@]}")" \
    --argjson mismatch "$(cog::fn::git_json_array_from_lines "${mismatch[@]}")" \
    --argjson commands "$(cog::fn::git_json_object_array_from_lines "${commands[@]}")" \
    --arg reason "$reason" \
    '{
      ok: $ok,
      repo_root: $repo_root,
      requested: $requested,
      session_files: $session_files,
      initial_staged: $initial_staged,
      unstaged: $unstaged,
      staged: $staged,
      restaged: $restaged,
      final_staged: $final_staged,
      mismatch: $mismatch,
      commands: $commands
    } + (if $ok then {} else {reason: $reason} end)'
}

cog::cmd::gc_stage() {
  local session_file="" repo_root_flag="" mode="" out="" json

  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_gc_stage_usage
        return 0
        ;;
      --session-files)
        [[ $# -ge 2 && -n ${2:-} && -z $session_file ]] || cog::fn::error_raise "MissingArgument" \
          "missing session files path" "option: --session-files" "" "run 'cog gc-stage --help'"
        session_file="$2"
        shift 2
        ;;
      --repo-root)
        [[ $# -ge 2 && -n ${2:-} && -z $repo_root_flag ]] || cog::fn::error_raise "MissingArgument" \
          "missing repo root" "option: --repo-root" "" "run 'cog gc-stage --help'"
        repo_root_flag="$2"
        shift 2
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" \
          "duplicate gc-stage output mode" "" "" "choose either --json or an output path"
        mode="json"
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown gc-stage option" "option: $1" "" "run 'cog gc-stage --help'"
        ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise "TooManyArguments" \
          "too many gc-stage output paths" "argument: $1" "" "run 'cog gc-stage --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done

  [[ -n $mode || ${COG_UI_JSON:-false} != true ]] || mode=json
  [[ -n $session_file && -n $mode ]] || cog::fn::error_raise "MissingArgument" \
    "missing gc-stage argument" "usage: cog gc-stage --session-files <file> (<out.json>|--json)" "" \
    "run 'cog gc-stage --help'"

  json="$(__cog_gc_stage_build_json "$session_file" "$repo_root_flag")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$__cog_gc_stage_self_check" "$json"
  else
    cog::fn::json_write_fragment "$out" "$__cog_gc_stage_self_check" "$json"
  fi
  jq -e '.ok == true' <<<"$json" >/dev/null
}
