# shellcheck shell=bash

__cog_git_require_git() {
  __have git || cog::helpers::die "$EX_UNAVAILABLE" "MissingRequirement" \
    "required command not found" "command: git" "" "install git and retry"
}

__cog_git_require_jq() {
  __have jq || cog::helpers::die "$EX_UNAVAILABLE" "MissingRequirement" \
    "required command not found" "command: jq" "" "install jq and retry"
}

__cog_git_json_array_from_lines() {
  __cog_git_require_jq
  if [[ $# -eq 0 ]]; then
    jq -cn '[]'
    return 0
  fi
  printf '%s\n' "$@" | jq -R . | jq -s .
}

__cog_git_json_object_array_from_lines() {
  __cog_git_require_jq
  if [[ $# -eq 0 ]]; then
    jq -cn '[]'
    return 0
  fi
  printf '%s\n' "$@" | jq -s .
}

__cog_git_bool() {
  case "$1" in
    true | false)
      printf '%s\n' "$1"
      ;;
    *)
      cog::helpers::die "$EX_SOFTWARE" "BadCall" \
        "invalid boolean" "value: ${1}" "" "report this cog bug"
      ;;
  esac
}

cog::fn::git_root() {
  __cog_git_require_git
  git rev-parse --show-toplevel
}

cog::fn::git_root_for() {
  local dir="${1:-}"
  [[ -n $dir && -d $dir ]] || return 1
  git -C "$dir" rev-parse --show-toplevel 2>/dev/null
}

cog::fn::git_current_branch() {
  __cog_git_require_git
  git branch --show-current
}

cog::fn::git_status_porcelain() {
  __cog_git_require_git
  git status --porcelain=v1 -uall
}

cog::fn::git_status_json() {
  __cog_git_require_git
  __cog_git_require_jq

  local root branch line xy payload path orig_path staged unstaged untracked json
  local -a files=()
  root="$(cog::fn::git_root)"
  branch="$(cog::fn::git_current_branch)"

  while IFS= read -r line; do
    [[ -n $line ]] || continue
    xy="${line:0:2}"
    payload="${line:3}"
    path="$payload"
    orig_path=""

    if [[ $payload == *" -> "* ]]; then
      orig_path="${payload%% -> *}"
      path="${payload#* -> }"
    fi

    staged=false
    unstaged=false
    untracked=false
    if [[ $xy == "??" ]]; then
      untracked=true
    else
      [[ ${xy:0:1} != " " ]] && staged=true
      [[ ${xy:1:1} != " " ]] && unstaged=true
    fi

    if [[ -n $orig_path ]]; then
      files+=("$(jq -cn \
        --arg xy "$xy" \
        --arg path "$path" \
        --arg orig_path "$orig_path" \
        --argjson staged "$(__cog_git_bool "$staged")" \
        --argjson unstaged "$(__cog_git_bool "$unstaged")" \
        --argjson untracked "$(__cog_git_bool "$untracked")" \
        '{xy: $xy, path: $path, orig_path: $orig_path, staged: $staged, unstaged: $unstaged, untracked: $untracked}')")
    else
      files+=("$(jq -cn \
        --arg xy "$xy" \
        --arg path "$path" \
        --argjson staged "$(__cog_git_bool "$staged")" \
        --argjson unstaged "$(__cog_git_bool "$unstaged")" \
        --argjson untracked "$(__cog_git_bool "$untracked")" \
        '{xy: $xy, path: $path, orig_path: null, staged: $staged, unstaged: $unstaged, untracked: $untracked}')")
    fi
  done < <(cog::fn::git_status_porcelain)

  json="$(jq -n \
    --arg root "$root" \
    --arg branch "$branch" \
    --argjson files "$(__cog_git_json_object_array_from_lines "${files[@]}")" \
    '{root: $root, branch: $branch, files: $files}')"
  cog::fn::json_validate 'has("root") and has("branch") and (.files | type == "array")' "$json" \
    || cog::helpers::die "$EX_SOFTWARE" "InvalidJsonOutput" \
      "invalid git status JSON" "function: cog::fn::git_status_json" "" "report this cog bug"
  printf '%s\n' "$json"
}

cog::fn::git_staged_files_json() {
  __cog_git_require_git
  local -a files=()
  mapfile -t files < <(git diff --staged --name-only)
  __cog_git_json_array_from_lines "${files[@]}"
}

cog::fn::git_unstaged_files_json() {
  __cog_git_require_git
  local -a files=()
  mapfile -t files < <(git diff --name-only)
  __cog_git_json_array_from_lines "${files[@]}"
}

cog::fn::git_diff_stat_json() {
  __cog_git_require_git
  __cog_git_require_jq

  local mode="unstaged"
  local -a git_args=()
  case "${1:---unstaged}" in
    --staged)
      mode="staged"
      git_args=(--staged)
      ;;
    --unstaged)
      mode="unstaged"
      ;;
    *)
      cog::helpers::die "$EX_USAGE" "InvalidInput" \
        "invalid git diff stat mode" "mode: ${1:-}" \
        "expected --staged or --unstaged" ""
      ;;
  esac

  local added deleted path json
  local -a files=()
  while IFS=$'\t' read -r added deleted path; do
    [[ -n ${path:-} ]] || continue
    [[ $added == "-" ]] && added=0
    [[ $deleted == "-" ]] && deleted=0
    files+=("$(jq -cn \
      --arg path "$path" \
      --argjson added "$added" \
      --argjson deleted "$deleted" \
      '{path: $path, added: $added, deleted: $deleted}')")
  done < <(git diff "${git_args[@]}" --numstat)

  json="$(jq -n \
    --arg mode "$mode" \
    --argjson files "$(__cog_git_json_object_array_from_lines "${files[@]}")" \
    '{mode: $mode, files: $files}')"
  cog::fn::json_validate '(.mode == "staged" or .mode == "unstaged") and (.files | type == "array")' "$json" \
    || cog::helpers::die "$EX_SOFTWARE" "InvalidJsonOutput" \
      "invalid git diff stat JSON" "function: cog::fn::git_diff_stat_json" "" "report this cog bug"
  printf '%s\n' "$json"
}

cog::fn::git_recent_log_json() {
  __cog_git_require_git
  __cog_git_require_jq

  local limit="${1:-10}"
  [[ $limit =~ ^[0-9]+$ ]] || cog::helpers::die "$EX_USAGE" "InvalidInput" \
    "invalid git log limit" "limit: ${limit}" "expected a nonnegative integer" ""

  local sha subject
  local -a commits=()
  while IFS=$'\t' read -r sha subject || [[ -n ${sha:-} ]]; do
    [[ -n ${sha:-} ]] || continue
    commits+=("$(jq -cn \
      --arg sha "$sha" \
      --arg subject "${subject:-}" \
      '{sha: $sha, subject: $subject}')")
  done < <(git log -n "$limit" --pretty=format:'%h%x09%s')

  __cog_git_json_object_array_from_lines "${commits[@]}"
}

cog::fn::git_classify_failure_log() {
  __cog_git_require_jq

  local log_file="${1:-}"
  [[ -n $log_file ]] || cog::helpers::die "$EX_USAGE" "MissingArgument" \
    "missing failure log path" "function: cog::fn::git_classify_failure_log" "" ""
  [[ -r $log_file ]] || cog::helpers::die "$EX_NOINPUT" "InputUnreadable" \
    "failure log is not readable" "path: ${log_file}" "" "check the log path"

  local content class reason retryable requires_judgment recommended_action
  local -a matched=()
  content="$(<"$log_file")"

  class="unknown"
  reason="could not classify failure log"
  retryable=false
  requires_judgment=true
  recommended_action="inspect the log and decide the next step"

  if grep -Eqi 'Author identity unknown|Please tell me who you are|gpg failed to sign the data|secret key not available|error: cannot spawn|fatal: not a git repository|fatal: this operation must be run in a work tree|error: invalid key:' <<<"$content"; then
    class="setup-missing"
    reason="git setup prerequisite is missing"
    retryable=false
    requires_judgment=false
    recommended_action="ask the user to fix git identity, signing, or repository setup"
    matched+=("setup-missing")
  elif grep -Eqi "No configured push destination|has no upstream branch|does not appear to be a git repository|Could not read from remote repository|Permission denied \(publickey\)|could not read Username|Authentication failed|Repository not found" <<<"$content"; then
    class="push-setup-missing"
    reason="push setup or credentials are missing"
    retryable=false
    requires_judgment=false
    recommended_action="ask the user to configure remote, upstream, or credentials"
    matched+=("push-setup-missing")
  elif grep -Eqi 'files were modified by this hook|reformatted|reformatted .*file|Fixing|Fixed .*file|would reformat|All done!.*reformatted|prettier.*(fixed|wrote)|black.*reformatted|shfmt.*(wrote|formatted)' <<<"$content"; then
    class="auto-fixer"
    reason="hook modified files automatically"
    retryable=true
    requires_judgment=false
    recommended_action="re-stage affected session files and retry"
    matched+=("auto-fixer")
  elif grep -Eqi 'commit-msg|subject is too long|Commit subject is too long|subject_length|disallowed type|Disallowed type|subject is punctuated|subject is capitalized|conventional commit|commit message' <<<"$content"; then
    class="commit-message"
    reason="commit message hook rejected the message"
    retryable=true
    requires_judgment=true
    recommended_action="revise the commit message according to hook output"
    matched+=("commit-message")
  elif grep -Eqi '(^|[^[:alnum:]_])(shellcheck|mypy|eslint|pytest|markdownlint|ruff)([^[:alnum:]_]|$)|(^|[^[:alnum:]_])bats[[:space:]].*(failed|Failed)|cargo test|go test|SC[0-9]{4}' <<<"$content"; then
    class="content-fix"
    reason="hook reported content issues"
    retryable=true
    requires_judgment=true
    recommended_action="fix reported issues in session files"
    matched+=("content-fix")
  elif grep -Eqi 'pre-push|pre push|prepush|hook id: pre-push|remote hook declined' <<<"$content"; then
    class="push-hook"
    reason="pre-push hook failed"
    retryable=true
    requires_judgment=true
    recommended_action="fix reported pre-push hook issues and retry"
    matched+=("push-hook")
  elif grep -Eqi 'non-fast-forward|fetch first|remote rejected|failed to push some refs|TLS|SSL|Connection timed out|Could not resolve host|network' <<<"$content"; then
    class="push-non-hook"
    reason="push failed for a non-hook reason"
    retryable=false
    requires_judgment=false
    recommended_action="report the push failure to the user"
    matched+=("push-non-hook")
  elif grep -Eqi 'ANALYSIS GATE.*STUCK|repeated signature|wall-clock cap|same meaningful errors repeat' <<<"$content"; then
    class="stuck"
    reason="failure log indicates the progress gate is stuck"
    retryable=false
    requires_judgment=true
    recommended_action="escalate per the skill progress-gate guidance"
    matched+=("stuck")
  fi

  jq -n \
    --arg class "$class" \
    --arg reason "$reason" \
    --arg log "$log_file" \
    --argjson matched "$(__cog_git_json_array_from_lines "${matched[@]}")" \
    --argjson retryable "$retryable" \
    --argjson requires_judgment "$requires_judgment" \
    --arg recommended_action "$recommended_action" \
    '{
      class: $class,
      reason: $reason,
      log: $log,
      matched: $matched,
      retryable: $retryable,
      requires_judgment: $requires_judgment,
      recommended_action: $recommended_action
    }'
}
