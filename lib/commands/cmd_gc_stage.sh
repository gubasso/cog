# shellcheck shell=bash
: 'desc: Reconcile and stage explicit session files.'

__cog_gc_stage_self_check='.ok != null and (.session_files | type == "array") and (.final_staged | type == "array")'

__cog_gc_stage_usage() {
  cog::fn::ui_data "Usage: cog gc-stage --session-files <file> (<out.json>|--json)"
}

__cog_gc_stage_json_array() {
  if (($# == 0)); then
    jq -cn '[]'
  else
    printf '%s\n' "$@" | jq -R . | jq -s .
  fi
}

__cog_gc_stage_json_objects() {
  if (($# == 0)); then
    jq -cn '[]'
  else
    printf '%s\n' "$@" | jq -s .
  fi
}

__cog_gc_stage_contains() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do
    [[ $item == "$needle" ]] && return 0
  done
  return 1
}

__cog_gc_stage_read_session_files() {
  local out_name="$1"
  local file="$2"
  local -n __out_ref="$out_name"
  local line segment
  __out_ref=()

  [[ -r $file ]] || cog::fn::error_raise "InputUnreadable" \
    "session files file is not readable" "path: ${file}" "" "check the file path"
  if od -An -tx1 "$file" | grep -q ' 00'; then
    cog::fn::error_raise "InvalidInput" \
      "session files file contains NUL bytes" "path: ${file}" "" "write newline-delimited paths"
  fi

  while IFS= read -r line || [[ -n $line ]]; do
    [[ -n $line ]] || continue
    [[ $line != /* ]] || cog::fn::error_raise "InvalidInput" \
      "session path must be repo-relative" "path: ${line}" "" "remove the leading slash"
    IFS='/' read -ra segments <<<"$line"
    for segment in "${segments[@]}"; do
      [[ $segment != ".." ]] || cog::fn::error_raise "InvalidInput" \
        "session path must not contain .." "path: ${line}" "" "pass repo-relative paths only"
    done
    __cog_gc_stage_contains "$line" "${__out_ref[@]}" || __out_ref+=("$line")
  done <"$file"

  ((${#__out_ref[@]} > 0)) || cog::fn::error_raise "InvalidInput" \
    "session files list is empty" "path: ${file}" "" "write at least one path"
}

__cog_gc_stage_command_object() {
  local action="$1"
  local path="$2"
  jq -cn --arg action "$action" --arg path "$path" '{action: $action, path: $path}'
}

__cog_gc_stage_build_json() {
  local session_file="$1"
  local root staged_path session_path final_path ok=true reason=""
  local -a session_files=() initial_staged=() final_staged=() unstaged=() staged=() mismatch=() commands=()

  root="$(cog::fn::git_root)"
  __cog_gc_stage_read_session_files session_files "$session_file"
  mapfile -t initial_staged < <(git diff --staged --name-only)

  for staged_path in "${initial_staged[@]}"; do
    if ! __cog_gc_stage_contains "$staged_path" "${session_files[@]}"; then
      if git reset HEAD -- "$staged_path" >/dev/null; then
        unstaged+=("$staged_path")
        commands+=("$(__cog_gc_stage_command_object unstage "$staged_path")")
      fi
    fi
  done

  mapfile -t final_staged < <(git diff --staged --name-only)
  for session_path in "${session_files[@]}"; do
    if ! __cog_gc_stage_contains "$session_path" "${final_staged[@]}"; then
      if git add -- "$session_path"; then
        staged+=("$session_path")
        commands+=("$(__cog_gc_stage_command_object stage "$session_path")")
      fi
    fi
  done

  mapfile -t final_staged < <(git diff --staged --name-only)
  for final_path in "${final_staged[@]}"; do
    __cog_gc_stage_contains "$final_path" "${session_files[@]}" || mismatch+=("$final_path")
  done
  for session_path in "${session_files[@]}"; do
    __cog_gc_stage_contains "$session_path" "${final_staged[@]}" || mismatch+=("$session_path")
  done

  if ((${#mismatch[@]} > 0 || ${#final_staged[@]} != ${#session_files[@]})); then
    ok=false
    reason="final staged set differs from session files"
  fi

  jq -n \
    --argjson ok "$ok" \
    --arg repo_root "$root" \
    --argjson session_files "$(__cog_gc_stage_json_array "${session_files[@]}")" \
    --argjson initial_staged "$(__cog_gc_stage_json_array "${initial_staged[@]}")" \
    --argjson unstaged "$(__cog_gc_stage_json_array "${unstaged[@]}")" \
    --argjson staged "$(__cog_gc_stage_json_array "${staged[@]}")" \
    --argjson final_staged "$(__cog_gc_stage_json_array "${final_staged[@]}")" \
    --argjson mismatch "$(__cog_gc_stage_json_array "${mismatch[@]}")" \
    --argjson commands "$(__cog_gc_stage_json_objects "${commands[@]}")" \
    --arg reason "$reason" \
    '{
      ok: $ok,
      repo_root: $repo_root,
      session_files: $session_files,
      initial_staged: $initial_staged,
      unstaged: $unstaged,
      staged: $staged,
      final_staged: $final_staged,
      mismatch: $mismatch,
      commands: $commands
    } + (if $ok then {} else {reason: $reason} end)'
}

cog::cmd::gc_stage() {
  local session_file="" mode="" out="" json

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
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" \
          "duplicate gc-stage output mode" "" "" "choose either --json or an output path"
        mode=json
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
        mode=file
        shift
        ;;
    esac
  done

  [[ -n $mode || ${COG_UI_JSON:-false} != true ]] || mode=json
  [[ -n $session_file && -n $mode ]] || cog::fn::error_raise "MissingArgument" \
    "missing gc-stage argument" "usage: cog gc-stage --session-files <file> (<out.json>|--json)" "" \
    "run 'cog gc-stage --help'"

  json="$(__cog_gc_stage_build_json "$session_file")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$__cog_gc_stage_self_check" "$json"
  else
    cog::fn::json_write_fragment "$out" "$__cog_gc_stage_self_check" "$json"
  fi
  jq -e '.ok == true' <<<"$json" >/dev/null
}
