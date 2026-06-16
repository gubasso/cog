# shellcheck shell=bash
: 'desc: Commit with a message file and explicit pathspec.'

__cog_gc_commit_self_check='.ok != null and (.paths | type == "array") and (.log | type == "string") and (.exit_code | type == "number")'

__cog_gc_commit_usage() {
  cog::fn::ui_data "Usage: cog gc-commit --message-file <file> --paths-file <file> (<out.json>|--json)"
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
  local root log_file sha="" exit_code ok
  local -a paths=()

  [[ -r $message_file ]] || cog::fn::error_raise "InputUnreadable" \
    "message file is not readable" "path: ${message_file}" "" "check the file path"
  __cog_gc_commit_read_paths paths "$paths_file"
  root="$(cog::fn::git_root)"
  log_file="$(__cog_gc_commit_new_log_file "$(__cog_gc_commit_log_dir)")"

  if git commit -F - -- "${paths[@]}" <"$message_file" >"$log_file" 2>&1; then
    ok=true
    exit_code=0
    sha="$(git rev-parse --short HEAD)"
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
    '{
      ok: $ok,
      repo_root: $repo_root,
      paths: $paths,
      sha: (if $ok then $sha else null end),
      log: $log,
      exit_code: $exit_code
    }'
}

cog::cmd::gc_commit() {
  local message_file="" paths_file="" mode="" out="" json

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
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" \
          "duplicate gc-commit output mode" "" "" "choose either --json or an output path"
        mode=json
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
        mode=file
        shift
        ;;
    esac
  done

  [[ -n $mode || ${COG_UI_JSON:-false} != true ]] || mode=json
  [[ -n $message_file && -n $paths_file && -n $mode ]] || cog::fn::error_raise "MissingArgument" \
    "missing gc-commit argument" "usage: cog gc-commit --message-file <file> --paths-file <file> (<out.json>|--json)" "" \
    "run 'cog gc-commit --help'"

  json="$(__cog_gc_commit_build_json "$message_file" "$paths_file")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$__cog_gc_commit_self_check" "$json"
  else
    cog::fn::json_write_fragment "$out" "$__cog_gc_commit_self_check" "$json"
  fi
  jq -e '.ok == true' <<<"$json" >/dev/null
}
