# shellcheck shell=bash
: 'desc: Commit with a message file and explicit pathspec.'

__cog_gc_commit_self_check='.ok != null and (.paths | type == "array") and (.log | type == "string") and (.exit_code | type == "number") and (.lint | type == "object")'

__cog_gc_commit_usage() {
  cog::fn::ui_data "Usage: cog gc-commit --message-file <file> --paths-file <file> [--repo-root <dir>] (<out.json>|--json)"
}

__cog_gc_commit_json_array() {
  if (($# == 0)); then
    jq -cn '[]'
  else
    printf '%s\n' "$@" | jq -R . | jq -s .
  fi
}

__cog_gc_commit_contains() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do
    [[ $item == "$needle" ]] && return 0
  done
  return 1
}

__cog_gc_commit_read_paths() {
  local out_name="$1"
  local file="$2"
  local -n __out_ref="$out_name"
  local line segment
  __out_ref=()

  [[ -r $file ]] || cog::fn::error_raise "InputUnreadable" \
    "paths file is not readable" "path: ${file}" "" "check the file path"
  if od -An -tx1 "$file" | grep -q ' 00'; then
    cog::fn::error_raise "InvalidInput" \
      "paths file contains NUL bytes" "path: ${file}" "" "write newline-delimited paths"
  fi

  while IFS= read -r line || [[ -n $line ]]; do
    [[ -n $line ]] || continue
    [[ $line != /* ]] || cog::fn::error_raise "InvalidInput" \
      "path must be repo-relative" "path: ${line}" "" "remove the leading slash"
    IFS='/' read -ra segments <<<"$line"
    for segment in "${segments[@]}"; do
      [[ $segment != ".." ]] || cog::fn::error_raise "InvalidInput" \
        "path must not contain .." "path: ${line}" "" "pass repo-relative paths only"
    done
    __cog_gc_commit_contains "$line" "${__out_ref[@]}" || __out_ref+=("$line")
  done <"$file"

  ((${#__out_ref[@]} > 0)) || cog::fn::error_raise "InvalidInput" \
    "paths file is empty" "path: ${file}" "" "write at least one path"
}

__cog_gc_commit_log_dir() {
  printf '%s/cog/skill-runs\n' "${XDG_RUNTIME_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}}"
}

__cog_gc_commit_new_log_file() {
  local dir="$1"
  local n=1
  mkdir -p "$dir" || cog::fn::error_raise "TempDirCreateFailed" \
    "could not create git commit log directory" "path: ${dir}" "" "check permissions"
  while [[ -e $dir/commit-hook-$$-$n.log ]]; do
    n=$((n + 1))
  done
  printf '%s/commit-hook-%s-%s.log\n' "$dir" "$$" "$n"
}

__cog_gc_commit_build_json() {
  local message_file="$1"
  local paths_file="$2"
  local repo_root_flag="${3:-}"
  local root log_file sha="" exit_code ok lint_json lint_ok
  local -a git_c=()
  local -a paths=()

  [[ -r $message_file ]] || cog::fn::error_raise "InputUnreadable" \
    "message file is not readable" "path: ${message_file}" "" "check the file path"
  __cog_gc_commit_read_paths paths "$paths_file"
  if [[ -n $repo_root_flag ]]; then
    root="$(cog::fn::git_root_for "$repo_root_flag")" || cog::fn::error_raise "InvalidInput" \
      "gc-commit: not a git worktree" "path: ${repo_root_flag}" "" "pass a git worktree root"
    git_c=(-C "$root")
  else
    root="$(cog::fn::git_root)"
  fi
  log_file="$(__cog_gc_commit_new_log_file "$(__cog_gc_commit_log_dir)")"

  # Conventional Commits pre-flight gate. A repo-native commit-message linter
  # prevails (the check defers); otherwise a non-conforming message fails closed
  # before git runs, surfacing violations for the skill to revise.
  lint_json="$(cog::fn::git_commit_msg_lint "$message_file" "$root")"
  lint_ok="$(jq -r '.ok' <<<"$lint_json")"

  if [[ $lint_ok != true ]]; then
    {
      printf 'commit message rejected by the Conventional Commits check\n'
      jq -r '.violations[] | "- [\(.code)] \(.message) -> \(.hint)"' <<<"$lint_json"
    } >"$log_file"
    ok=false
    exit_code=1
  elif cog::fn::env::exec "$root" "$(cog::fn::env::runner "$root")" -- \
    git "${git_c[@]}" commit -F - -- "${paths[@]}" <"$message_file" >"$log_file" 2>&1; then
    ok=true
    exit_code=0
    sha="$(git "${git_c[@]}" rev-parse --short HEAD)"
  else
    ok=false
    exit_code=1
  fi

  jq -n \
    --argjson ok "$ok" \
    --arg repo_root "$root" \
    --argjson paths "$(__cog_gc_commit_json_array "${paths[@]}")" \
    --arg sha "$sha" \
    --arg log "$log_file" \
    --argjson exit_code "$exit_code" \
    --argjson lint "$lint_json" \
    '{
      ok: $ok,
      repo_root: $repo_root,
      paths: $paths,
      sha: (if $ok then $sha else null end),
      log: $log,
      exit_code: $exit_code,
      lint: $lint
    }'
}

cog::cmd::gc_commit() {
  local message_file="" paths_file="" repo_root_flag="" mode="" out="" json

  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_gc_commit_usage
        return 0
        ;;
      --message-file)
        [[ $# -ge 2 && -n ${2:-} && -z $message_file ]] || cog::fn::error_raise "MissingArgument" \
          "missing message file" "option: --message-file" "" "run 'cog gc-commit --help'"
        message_file="$2"
        shift 2
        ;;
      --paths-file)
        [[ $# -ge 2 && -n ${2:-} && -z $paths_file ]] || cog::fn::error_raise "MissingArgument" \
          "missing paths file" "option: --paths-file" "" "run 'cog gc-commit --help'"
        paths_file="$2"
        shift 2
        ;;
      --repo-root)
        [[ $# -ge 2 && -n ${2:-} && -z $repo_root_flag ]] || cog::fn::error_raise "MissingArgument" \
          "missing repo root" "option: --repo-root" "" "run 'cog gc-commit --help'"
        repo_root_flag="$2"
        shift 2
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" \
          "duplicate gc-commit output mode" "" "" "choose either --json or an output path"
        mode="json"
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown gc-commit option" "option: $1" "" "run 'cog gc-commit --help'"
        ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise "TooManyArguments" \
          "too many gc-commit output paths" "argument: $1" "" "run 'cog gc-commit --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done

  [[ -n $mode || ${COG_UI_JSON:-false} != true ]] || mode=json
  [[ -n $message_file && -n $paths_file && -n $mode ]] || cog::fn::error_raise "MissingArgument" \
    "missing gc-commit argument" "usage: cog gc-commit --message-file <file> --paths-file <file> (<out.json>|--json)" "" \
    "run 'cog gc-commit --help'"

  json="$(__cog_gc_commit_build_json "$message_file" "$paths_file" "$repo_root_flag")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$__cog_gc_commit_self_check" "$json"
  else
    cog::fn::json_write_fragment "$out" "$__cog_gc_commit_self_check" "$json"
  fi
  jq -e '.ok == true' <<<"$json" >/dev/null
}
