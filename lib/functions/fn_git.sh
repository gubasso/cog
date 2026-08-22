# shellcheck shell=bash

__cog_git_require_git() {
  __have git || cog::helpers::die "$EX_UNAVAILABLE" "MissingRequirement" \
    "required command not found" "command: git" "" "install git and retry"
}

__cog_git_require_jq() {
  __have jq || cog::helpers::die "$EX_UNAVAILABLE" "MissingRequirement" \
    "required command not found" "command: jq" "" "install jq and retry"
}

cog::fn::git_json_array_from_lines() {
  __cog_git_require_jq
  if [[ $# -eq 0 ]]; then
    jq -cn '[]'
    return 0
  fi
  printf '%s\n' "$@" | jq -R . | jq -s .
}

cog::fn::git_json_object_array_from_lines() {
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

# Membership test over an argument list.
cog::fn::git_str_in_args() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do
    [[ $item == "$needle" ]] && return 0
  done
  return 1
}

# Membership test over a newline-delimited string, for callers that carry path
# sets as text (an associative array's value, say) rather than as an array.
cog::fn::git_str_in_lines() {
  case $'\n'"$2"$'\n' in
    *$'\n'"$1"$'\n'*) return 0 ;;
    *) return 1 ;;
  esac
}

# Read a newline-delimited session-files list into the named array, deduped and
# order-preserving. Blank lines are ignored; an unreadable file, a file holding
# NUL bytes, and an empty result each fail closed. Pass mode `relative` to also
# reject absolute paths and `..` segments, which is what the per-repo commands
# require; multi-repo callers pass `any` and resolve ownership themselves.
cog::fn::git_read_session_files() {
  local out_name="$1"
  local file="$2"
  local mode="${3:-any}"
  local -n __cog_git_session_out="$out_name"
  local line segment
  local -a segments=()
  __cog_git_session_out=()

  [[ -r $file ]] || cog::fn::error_raise "InputUnreadable" \
    "session files file is not readable" "path: ${file}" "" "check the file path"
  if od -An -tx1 "$file" | grep -q ' 00'; then
    cog::fn::error_raise "InvalidInput" \
      "session files file contains NUL bytes" "path: ${file}" "" "write newline-delimited paths"
  fi

  while IFS= read -r line || [[ -n $line ]]; do
    [[ -n $line ]] || continue
    if [[ $mode == relative ]]; then
      [[ $line != /* ]] || cog::fn::error_raise "InvalidInput" \
        "session path must be repo-relative" "path: ${line}" "" "remove the leading slash"
      IFS='/' read -ra segments <<<"$line"
      for segment in "${segments[@]}"; do
        [[ $segment != ".." ]] || cog::fn::error_raise "InvalidInput" \
          "session path must not contain .." "path: ${line}" "" "pass repo-relative paths only"
      done
    fi
    cog::fn::git_str_in_args "$line" "${__cog_git_session_out[@]}" \
      || __cog_git_session_out+=("$line")
  done <"$file"

  ((${#__cog_git_session_out[@]} > 0)) || cog::fn::error_raise "InvalidInput" \
    "session files list is empty" "path: ${file}" "" "write at least one path"
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

# Classify where a resolved git config key comes from: local (this repo's
# config), global (the user's ~/.gitconfig), else system (any other resolved
# scope). Only meaningful for a key that already resolves to a value.
__cog_git_identity_source() {
  local project_root="$1" key="$2"
  if git -C "$project_root" config --local --get "$key" >/dev/null 2>&1; then
    printf 'local\n'
  elif git -C "$project_root" config --global --get "$key" >/dev/null 2>&1; then
    printf 'global\n'
  else
    printf 'system\n'
  fi
}

# Resolve the repo's git identity for a project root, as git itself resolves it
# (a repo-local user.name/user.email overrides the global one — the same identity
# commits carry). Emits:
#   {ok, name, email, author_string, name_source, email_source, missing, reason}
# author_string is "<name> <email>" when both resolve, else null. ok is false —
# with name/email null and the unset fields listed in `missing` — when the root
# is not a git repo or either field is unset/empty. The human-facing step-by-step
# remediation lives in the shared git-identity preflight routine, not here: this
# helper reports the facts, the routine owns the wording.
cog::fn::git_identity_json() {
  __cog_git_require_git
  __cog_git_require_jq

  local project_root="${1:-$PWD}"
  local ok=true reason="" name="" email="" name_source="" email_source=""
  local -a missing=()

  if [[ ! -d $project_root ]]; then
    ok=false
    reason="project root is not a directory"
  elif ! git -C "$project_root" rev-parse --git-dir >/dev/null 2>&1; then
    ok=false
    reason="not a git repository"
  else
    name="$(git -C "$project_root" config --get user.name 2>/dev/null)" || name=""
    email="$(git -C "$project_root" config --get user.email 2>/dev/null)" || email=""
    [[ -n $name ]] && name_source="$(__cog_git_identity_source "$project_root" user.name)"
    [[ -n $email ]] && email_source="$(__cog_git_identity_source "$project_root" user.email)"
    [[ -n $name ]] || missing+=("user.name")
    [[ -n $email ]] || missing+=("user.email")
    if ((${#missing[@]} > 0)); then
      ok=false
      reason="git identity not configured: ${missing[*]} unset"
    fi
  fi

  jq -n \
    --argjson ok "$(__cog_git_bool "$ok")" \
    --arg project_root "$project_root" \
    --arg name "$name" \
    --arg email "$email" \
    --arg name_source "$name_source" \
    --arg email_source "$email_source" \
    --arg reason "$reason" \
    --argjson missing "$(cog::fn::git_json_array_from_lines "${missing[@]}")" \
    '{ok: $ok, project_root: $project_root,
      name: (if $name == "" then null else $name end),
      email: (if $email == "" then null else $email end),
      author_string: (if $name == "" or $email == "" then null else ($name + " <" + $email + ">") end),
      name_source: (if $name_source == "" then null else $name_source end),
      email_source: (if $email_source == "" then null else $email_source end),
      missing: $missing,
      reason: (if $ok then null else $reason end)}'
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
    --argjson files "$(cog::fn::git_json_object_array_from_lines "${files[@]}")" \
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
  cog::fn::git_json_array_from_lines "${files[@]}"
}

cog::fn::git_unstaged_files_json() {
  __cog_git_require_git
  local -a files=()
  mapfile -t files < <(git diff --name-only)
  cog::fn::git_json_array_from_lines "${files[@]}"
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

  # --no-renames for the same reason the commit selectors use it: plain
  # --numstat renders a rename as the single literal "old.txt => new.txt",
  # which is not a path any consumer can open.
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
  done < <(git diff "${git_args[@]}" --numstat --no-renames)

  json="$(jq -n \
    --arg mode "$mode" \
    --argjson files "$(cog::fn::git_json_object_array_from_lines "${files[@]}")" \
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

  cog::fn::git_json_object_array_from_lines "${commits[@]}"
}

# Emit a JSON array of commits for the given ranges and/or explicit SHAs, each
# parsed into Conventional Commits fields:
#   [{sha, short, subject, body, type, scope, description, breaking}]
# Ranges walk normally; explicit SHAs resolve with --no-walk so non-contiguous
# selections list once each. Commits selected more than once are de-duplicated,
# first occurrence wins. `--repo <dir>` runs git in that worktree.
cog::fn::git_log_range_json() {
  __cog_git_require_git
  __cog_git_require_jq

  local repo=""
  local -a ranges=() shas=()
  while (($# > 0)); do
    case "$1" in
      --repo)
        [[ $# -ge 2 ]] || cog::helpers::die "$EX_USAGE" "MissingArgument" \
          "missing --repo value" "option: --repo" "" "pass a worktree path"
        repo="$2"
        shift 2
        ;;
      --range)
        [[ $# -ge 2 ]] || cog::helpers::die "$EX_USAGE" "MissingArgument" \
          "missing --range value" "option: --range" "" "pass a git range like A..B"
        ranges+=("$2")
        shift 2
        ;;
      --sha)
        [[ $# -ge 2 ]] || cog::helpers::die "$EX_USAGE" "MissingArgument" \
          "missing --sha value" "option: --sha" "" "pass a commit sha"
        shas+=("$2")
        shift 2
        ;;
      *)
        cog::helpers::die "$EX_USAGE" "InvalidInput" \
          "unknown git_log_range_json option" "option: $1" "" "use --repo, --range, or --sha"
        ;;
    esac
  done

  if ((${#ranges[@]} + ${#shas[@]} == 0)); then
    jq -cn '[]'
    return 0
  fi

  local -a gitcmd=(git)
  [[ -n $repo ]] && gitcmd=(git -C "$repo")
  local fmt='%H%x1f%h%x1f%s%x1f%b'

  local -a recs=()
  if ((${#ranges[@]} > 0)); then
    local -a range_recs=()
    mapfile -d '' -t range_recs < <("${gitcmd[@]}" log -z --format="$fmt" "${ranges[@]}" 2>/dev/null || true)
    recs+=("${range_recs[@]}")
  fi
  if ((${#shas[@]} > 0)); then
    local -a sha_recs=()
    mapfile -d '' -t sha_recs < <("${gitcmd[@]}" log -z --no-walk --format="$fmt" "${shas[@]}" 2>/dev/null || true)
    recs+=("${sha_recs[@]}")
  fi

  local rec sha short subject body rest parsed obj
  local -a objs=()
  for rec in "${recs[@]}"; do
    [[ -n $rec ]] || continue
    sha="${rec%%$'\x1f'*}"
    rest="${rec#*$'\x1f'}"
    short="${rest%%$'\x1f'*}"
    rest="${rest#*$'\x1f'}"
    subject="${rest%%$'\x1f'*}"
    body="${rest#*$'\x1f'}"
    parsed="$(cog::fn::git_parse_conventional_subject "$subject")"
    obj="$(jq -cn \
      --arg sha "$sha" \
      --arg short "$short" \
      --arg subject "$subject" \
      --arg body "$body" \
      --argjson cc "$parsed" \
      '{sha: $sha, short: $short, subject: $subject, body: $body,
        type: $cc.type, scope: $cc.scope, description: $cc.description,
        breaking: $cc.breaking}')"
    objs+=("$obj")
  done

  cog::fn::git_json_object_array_from_lines "${objs[@]}" \
    | jq -c 'reduce .[] as $c ([]; if any(.[]; .sha == $c.sha) then . else . + [$c] end)'
}

# Shared argv parsing for the commit-selector helpers below. Fills the caller's
# repo string and ranges/shas arrays by name so the two helpers that accept the
# same grammar cannot drift apart.
__cog_git_range_argv() {
  local -n __cog_range_repo="$1"
  local -n __cog_range_ranges="$2"
  local -n __cog_range_shas="$3"
  shift 3

  __cog_range_repo=""
  __cog_range_ranges=()
  __cog_range_shas=()

  while (($# > 0)); do
    case "$1" in
      --repo)
        [[ $# -ge 2 ]] || cog::helpers::die "$EX_USAGE" "MissingArgument" \
          "missing --repo value" "option: --repo" "" "pass a worktree path"
        __cog_range_repo="$2"
        shift 2
        ;;
      --range)
        [[ $# -ge 2 ]] || cog::helpers::die "$EX_USAGE" "MissingArgument" \
          "missing --range value" "option: --range" "" "pass a git range like A..B"
        __cog_range_ranges+=("$2")
        shift 2
        ;;
      --sha)
        [[ $# -ge 2 ]] || cog::helpers::die "$EX_USAGE" "MissingArgument" \
          "missing --sha value" "option: --sha" "" "pass a commit sha"
        __cog_range_shas+=("$2")
        shift 2
        ;;
      *)
        cog::helpers::die "$EX_USAGE" "InvalidInput" \
          "unknown git commit selector option" "option: $1" "" "use --repo, --range, or --sha"
        ;;
    esac
  done
}

# Run one selector's git command and return its stdout, raising when the
# selector does not resolve. cog::fn::git_log_range_json swallows git's exit
# status because a missing commit there costs a log entry; here it would cost
# the whole changeset and read as a clean review, so it fails loudly instead.
__cog_git_range_capture() {
  local -n __cog_range_out="$1"
  local selector="$2"
  shift 2
  local status

  # The output lands in the caller's variable rather than on stdout: a die from
  # inside a command substitution would only kill the subshell, and the caller
  # would go on to report an empty changeset for an unresolvable ref.
  # The `|| status=$?` is load-bearing under errexit: a bare failing assignment
  # would terminate the shell with git's own status before this check runs, and
  # the caller would see a raw 128 with no cog error at all.
  status=0
  __cog_range_out="$("$@" 2>/dev/null)" || status=$?
  ((status == 0)) || cog::helpers::die "$EX_DATAERR" "InvalidInput" \
    "could not resolve git commit selector" "selector: ${selector}" \
    "git exited ${status}" "check the ref and retry"
}

# Peel every commit selector to the commit it names, replacing the caller's
# array in place, and fail when a selector names a non-commit object. `git show`
# will happily print a blob's contents, and `--name-only`/`--numstat` do not
# suppress that, so `--sha <tree-ish>:<path>` would otherwise land the file's own
# text in commit_files as though every line were a path. Peeling also pins an
# annotated tag or a movable branch name to the commit it resolved to, which is
# what lets a caller resolve once and reuse the result across several helpers
# instead of re-resolving a ref that can move between them. Runs only when there
# is at least one selector, so a caller with none still issues no git command
# from here. Peeling is idempotent: a full commit hash peels to itself.
cog::fn::git_peel_commit_selectors() {
  __cog_git_require_git

  local -n __cog_range_peel="$1"
  local repo="${2:-}"
  local i peeled status

  ((${#__cog_range_peel[@]} > 0)) || return 0

  local -a gitcmd=(git)
  [[ -n $repo ]] && gitcmd=(git -C "$repo")

  for i in "${!__cog_range_peel[@]}"; do
    status=0
    peeled="$("${gitcmd[@]}" rev-parse --verify --quiet "${__cog_range_peel[i]}^{commit}" 2>/dev/null)" || status=$?
    # Same headline the capture path raises, because a selector that names a
    # blob and a selector that names nothing are one failure to the caller: it
    # is not a commit this scope can read. Only the `why` line distinguishes.
    { ((status == 0)) && [[ -n $peeled ]]; } || cog::helpers::die "$EX_DATAERR" "InvalidInput" \
      "could not resolve git commit selector" "selector: ${__cog_range_peel[i]}" \
      "it does not name a commit" "pass a commit sha, tag, or branch"
    __cog_range_peel["$i"]="$peeled"
  done
}

# The diff semantics every commit selector is read with. This is one array
# shared by both public helpers below, because two invocations describing one
# diff is exactly how commit_files and diff_stats.commits came to disagree.
#
# --numstat carries the path in its third field, so it answers "which files" and
# "how many lines" at once; --name-only is not needed and, on a merge, does not
# agree with it. --no-renames reports a rename as a delete plus an add of two
# real paths, instead of the single literal "old.txt => new.txt" that names no
# file on disk; it over-counts a renamed file's lines, which is the safe
# direction for a review budget. --first-parent states the merge semantics
# rather than inheriting them: git show reaches for a combined diff on a merge
# on its own, and that is what made a merge's files vanish from the file list.
__cog_git_numstat_opts=(--numstat --no-renames --first-parent)

# Fill the caller's variable with [{path, added, deleted}], one record per
# numstat line, for every selector in the caller's ranges and shas arrays. The
# single source both public helpers read: neither issues a git command of its
# own, so they cannot disagree.
#
# The result lands in a named variable rather than on stdout for the same reason
# __cog_git_range_capture does it: a die from inside a command substitution or a
# pipeline kills only the subshell, and the caller would carry on with an empty
# record set — an unresolvable ref reported as a clean scope.
__cog_git_range_numstat_json() {
  local -n __cog_ns_out="$1"
  local -n __cog_ns_ranges="$2"
  local -n __cog_ns_shas="$3"
  local repo="${4:-}"

  local -a gitcmd=(git)
  [[ -n $repo ]] && gitcmd=(git -C "$repo")

  local selector out added deleted path
  local -a recs=()
  for selector in "${__cog_ns_ranges[@]}"; do
    __cog_git_range_capture out "$selector" \
      "${gitcmd[@]}" diff "${__cog_git_numstat_opts[@]}" "$selector" --
    while IFS=$'\t' read -r added deleted path; do
      [[ -n ${path:-} ]] || continue
      [[ $added == "-" ]] && added=0
      [[ $deleted == "-" ]] && deleted=0
      recs+=("$(jq -cn --arg path "$path" --argjson added "$added" --argjson deleted "$deleted" \
        '{path: $path, added: $added, deleted: $deleted}')")
    done <<<"$out"
  done
  for selector in "${__cog_ns_shas[@]}"; do
    __cog_git_range_capture out "$selector" \
      "${gitcmd[@]}" show "${__cog_git_numstat_opts[@]}" --format= "$selector" --
    while IFS=$'\t' read -r added deleted path; do
      [[ -n ${path:-} ]] || continue
      [[ $added == "-" ]] && added=0
      [[ $deleted == "-" ]] && deleted=0
      recs+=("$(jq -cn --arg path "$path" --argjson added "$added" --argjson deleted "$deleted" \
        '{path: $path, added: $added, deleted: $deleted}')")
    done <<<"$out"
  done

  __cog_ns_out="$(cog::fn::git_json_object_array_from_lines "${recs[@]}")"
}

# Emit {files: [path, ...], stat: {mode: "range", files: [{path, added, deleted}]}}
# for the given ranges and/or SHAs: the file list and the line stats of one
# diff, read from one numstat record set per selector.
#
# Both answers come back together because they are one answer. Returning them
# from separate functions meant two git invocations per selector, and on a merge
# those two invocations disagreed — the file list came back empty while the
# stats named a file, so the reviewer never opened a file the budget was charged
# for. A caller that receives both at once cannot reintroduce that gap.
#
# `files` is de-duplicated and sorted; `stat.files` is summed per path and
# sorted by path. With no selector this returns the empty pair without invoking
# git at all, which is what keeps the default review-scope path unchanged.
cog::fn::git_range_scope_json() {
  __cog_git_require_git
  __cog_git_require_jq

  local repo=""
  local -a ranges=() shas=()
  __cog_git_range_argv repo ranges shas "$@"

  local records='[]'
  if ((${#ranges[@]} + ${#shas[@]} > 0)); then
    cog::fn::git_peel_commit_selectors shas "$repo"
    __cog_git_range_numstat_json records ranges shas "$repo"
  fi

  local json
  json="$(jq -n --argjson records "$records" \
    '{
      files: ($records | [.[].path] | unique),
      stat: {
        mode: "range",
        files: ($records
          | group_by(.path)
          | map({
              path: .[0].path,
              added: (map(.added) | add),
              deleted: (map(.deleted) | add)
            }))
      }
    }')"
  cog::fn::json_validate '(.files | type == "array") and (.stat.mode == "range") and (.stat.files | type == "array")' "$json" \
    || cog::helpers::die "$EX_SOFTWARE" "InvalidJsonOutput" \
      "invalid git range scope JSON" "function: cog::fn::git_range_scope_json" "" "report this cog bug"
  printf '%s\n' "$json"
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
    --argjson matched "$(cog::fn::git_json_array_from_lines "${matched[@]}")" \
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

# --- Round-loop progress ------------------------------------------------------
#
# Extract a stable set of failure signatures from one commit/push report so two
# consecutive round reports can be diffed. A failing pre-commit hook prints a
# `- hook id: <id>` line; the hook id is a stable identifier free of volatile
# paths or line numbers. When a report carries no hook ids (a git-native or
# commit-message failure) the failure class stands in as the signature.
cog::fn::git_loop_signatures() {
  __cog_git_require_jq

  local log_file="${1:-}"
  [[ -n $log_file ]] || cog::helpers::die "$EX_USAGE" "MissingArgument" \
    "missing failure log path" "function: cog::fn::git_loop_signatures" "" ""
  [[ -r $log_file ]] || cog::helpers::die "$EX_NOINPUT" "InputUnreadable" \
    "failure log is not readable" "path: ${log_file}" "" "check the log path"

  local -a sigs=()
  local id
  while IFS= read -r id; do
    [[ -n $id ]] || continue
    sigs+=("hook:$id")
  done < <(grep -Eo '^[[:space:]]*-[[:space:]]*hook id:[[:space:]]*[A-Za-z0-9._-]+' "$log_file" \
    | sed -E 's/.*hook id:[[:space:]]*//' | awk '!seen[$0]++')

  if [[ ${#sigs[@]} -eq 0 ]]; then
    local class
    class="$(cog::fn::git_classify_failure_log "$log_file" | jq -r '.class')"
    [[ $class == unknown ]] || sigs+=("class:$class")
  fi

  cog::fn::git_json_array_from_lines "${sigs[@]}"
}

cog::fn::git_loop_progress() {
  __cog_git_require_jq

  local current_file="${1:-}" previous_file="${2:-}" current previous
  [[ -n $current_file && -n $previous_file ]] || cog::helpers::die "$EX_USAGE" \
    "MissingArgument" "missing loop-progress log path" \
    "function: cog::fn::git_loop_progress" "" ""

  current="$(cog::fn::git_loop_signatures "$current_file")"
  previous="$(cog::fn::git_loop_signatures "$previous_file")"

  jq -n --argjson current "$current" --argjson previous "$previous" '
    (($current | unique)) as $cur |
    (($previous | unique)) as $prev |
    ($cur - $prev) as $new |
    ($cur - ($cur - $prev)) as $recurring |
    ($prev - $cur) as $resolved |
    (($cur | length) + ($prev | length) | if . == 0 then 1 else . end) as $denom |
    {
      new: $new,
      recurring: $recurring,
      resolved: $resolved,
      churn_ratio: ((($new | length) + ($resolved | length)) / $denom),
      counts: {
        current: ($cur | length),
        previous: ($prev | length),
        new: ($new | length),
        recurring: ($recurring | length),
        resolved: ($resolved | length)
      }
    }
  '
}

# --- Conventional Commits message validation ----------------------------------
#
# A deterministic Conventional Commits check that backstops the commit-message
# judgment in the gc skill. The user's own commit-message linter always prevails:
# when one governs the repo the check defers and applies no rules of its own. Rule
# values (allowed types, length caps) come from `committed.toml` — the project's if
# present, else the shipped template — keeping it the single source of truth.

# Default rule values (mirror skill-refs/templates/pre-commit/committed.toml). Used
# only as a last resort when no committed.toml resolves.
__cog_cc_default_types=(feat fix docs style refactor perf test build ci chore revert)

# Parse the committed.toml subset we use. Sets CC_ALLOWED_TYPES, CC_ALLOWED_SCOPES,
# CC_LINE_LENGTH, CC_SUBJECT_CAPITALIZED, CC_SUBJECT_NOT_PUNCTUATED. Unset keys stay
# empty so the caller can fall back to defaults. Returns 1 if the file is unreadable.
__cog_git_read_committed_config() {
  local file="$1"
  CC_ALLOWED_TYPES=()
  CC_ALLOWED_SCOPES=()
  CC_LINE_LENGTH=""
  CC_SUBJECT_CAPITALIZED=""
  CC_SUBJECT_NOT_PUNCTUATED=""
  [[ -r $file ]] || return 1

  local nocomment
  nocomment="$(sed -E 's/(^|[[:space:]])#.*$//' "$file")"

  mapfile -t CC_ALLOWED_TYPES < <(
    awk '/^[[:space:]]*allowed_types[[:space:]]*=/{f=1} f{print} f&&/\]/{exit}' "$file" \
      | grep -oE '"[^"]+"' | tr -d '"'
  )
  mapfile -t CC_ALLOWED_SCOPES < <(
    awk '/^[[:space:]]*allowed_scopes[[:space:]]*=/{f=1} f{print} f&&/\]/{exit}' "$file" \
      | grep -oE '"[^"]+"' | tr -d '"'
  )
  CC_LINE_LENGTH="$(grep -E '^[[:space:]]*line_length[[:space:]]*=' <<<"$nocomment" | grep -oE '[0-9]+' | head -1)"
  CC_SUBJECT_CAPITALIZED="$(grep -E '^[[:space:]]*subject_capitalized[[:space:]]*=' <<<"$nocomment" | grep -oE 'true|false' | head -1)"
  CC_SUBJECT_NOT_PUNCTUATED="$(grep -E '^[[:space:]]*subject_not_punctuated[[:space:]]*=' <<<"$nocomment" | grep -oE 'true|false' | head -1)"
  return 0
}

# Detect an existing commit-message linter that should prevail. Prints two lines:
# the linter name (empty if none) and its config path (empty if none). Filesystem
# only — a project `committed.toml` is NOT a deference trigger; its rules are used.
__cog_git_detect_commit_linter() {
  local root="$1"
  local linter="" config=""
  if [[ -n $root && -d $root ]]; then
    if [[ -x $root/.git/hooks/commit-msg ]]; then
      linter="commit-msg-hook"
      config="$root/.git/hooks/commit-msg"
    elif [[ -f $root/.pre-commit-config.yaml ]] \
      && grep -Eq 'commit-msg|committed|commitlint|conventional-pre-commit|gitlint' "$root/.pre-commit-config.yaml"; then
      linter="pre-commit"
      config="$root/.pre-commit-config.yaml"
    else
      local f
      for f in commitlint.config.js commitlint.config.cjs commitlint.config.mjs commitlint.config.ts \
        .commitlintrc .commitlintrc.json .commitlintrc.yaml .commitlintrc.yml .commitlintrc.js .commitlintrc.cjs; do
        if [[ -f $root/$f ]]; then
          linter="commitlint"
          config="$root/$f"
          break
        fi
      done
      [[ -z $linter && -f $root/.gitlint ]] && {
        linter="gitlint"
        config="$root/.gitlint"
      }
      [[ -z $linter && -f $root/.conform.yaml ]] && {
        linter="conform"
        config="$root/.conform.yaml"
      }
    fi
  fi
  printf '%s\n%s\n' "$linter" "$config"
}

__cog_cc_add_violation() {
  CC_VIOLATIONS+=("$(jq -cn --arg c "$1" --arg m "$2" --arg h "$3" '{code: $c, message: $m, hint: $h}')")
}

# Parse a Conventional Commits subject line into its components. Pure and
# deterministic; the shared single source of truth for both the commit-message
# linter and the range-log helper. Emits one JSON object:
#   {sep_present, stem, type, scope, description, breaking,
#    space_after_colon, after_empty, scope_malformed}
# `stem` is the pre-colon text after stripping a breaking-change '!'.
# `space_after_colon` is false only when text follows the colon with no leading
# space; `after_empty` marks an empty post-colon remainder.
cog::fn::git_parse_conventional_subject() {
  __cog_git_require_jq

  local subject="${1:-}"
  local sep_present=false breaking=false space_after_colon=true after_empty=false scope_malformed=false
  local stem="" type="" scope="" desc=""

  if [[ $subject == *:* ]]; then
    sep_present=true
    local before="${subject%%:*}" after="${subject#*:}"

    if [[ -z $after ]]; then
      after_empty=true
      desc=""
    elif [[ $after == " "* ]]; then
      desc="${after# }"
    else
      desc="$after"
      space_after_colon=false
    fi

    # Strip an optional breaking-change '!' before parsing the scope.
    [[ $before == *"!" ]] && {
      breaking=true
      before="${before%!}"
    }

    stem="$before"
    type="$before"
    if [[ $before == *"("* || $before == *")"* ]]; then
      if [[ $before =~ ^([A-Za-z0-9_-]+)\((.+)\)$ ]]; then
        type="${BASH_REMATCH[1]}"
        scope="${BASH_REMATCH[2]}"
      else
        type="${before%%(*}"
        scope_malformed=true
      fi
    fi
  fi

  jq -cn \
    --argjson sep_present "$sep_present" \
    --arg stem "$stem" \
    --arg type "$type" \
    --arg scope "$scope" \
    --arg description "$desc" \
    --argjson breaking "$breaking" \
    --argjson space_after_colon "$space_after_colon" \
    --argjson after_empty "$after_empty" \
    --argjson scope_malformed "$scope_malformed" \
    '{sep_present: $sep_present, stem: $stem, type: $type, scope: $scope,
      description: $description, breaking: $breaking,
      space_after_colon: $space_after_colon, after_empty: $after_empty,
      scope_malformed: $scope_malformed}'
}

# Validate a commit message file against Conventional Commits, deferring to a
# repo-native linter when one is present. Emits:
#   {ok, deferred, linter, config, violations: [{code, message, hint}]}
cog::fn::git_commit_msg_lint() {
  __cog_git_require_jq

  local message_file="${1:-}" repo_root="${2:-}"
  [[ -n $message_file ]] || cog::helpers::die "$EX_USAGE" "MissingArgument" \
    "missing commit message path" "function: cog::fn::git_commit_msg_lint" "" ""
  [[ -r $message_file ]] || cog::helpers::die "$EX_NOINPUT" "InputUnreadable" \
    "commit message file is not readable" "path: ${message_file}" "" "check the message path"

  local root=""
  if [[ -n $repo_root ]]; then
    root="$(cog::fn::git_root_for "$repo_root" 2>/dev/null)" || root=""
  else
    root="$(cog::fn::git_root 2>/dev/null)" || root=""
  fi

  local linter config
  {
    read -r linter
    read -r config
  } < <(__cog_git_detect_commit_linter "$root")
  if [[ -n $linter ]]; then
    jq -n --arg linter "$linter" --arg config "$config" \
      '{ok: true, deferred: true, linter: $linter, config: $config, violations: []}'
    return 0
  fi

  # Resolve rule source: project committed.toml, else the shipped template.
  local config_file=""
  if [[ -n $root && -f $root/committed.toml ]]; then
    config_file="$root/committed.toml"
  else
    config_file="$(cog::fn::skill_refs_path templates/pre-commit/committed.toml 2>/dev/null || true)"
  fi
  local CC_ALLOWED_TYPES=() CC_ALLOWED_SCOPES=() CC_LINE_LENGTH="" CC_SUBJECT_CAPITALIZED="" CC_SUBJECT_NOT_PUNCTUATED=""
  [[ -n $config_file ]] && __cog_git_read_committed_config "$config_file"
  ((${#CC_ALLOWED_TYPES[@]} > 0)) || CC_ALLOWED_TYPES=("${__cog_cc_default_types[@]}")
  [[ $CC_LINE_LENGTH =~ ^[0-9]+$ ]] || CC_LINE_LENGTH=72
  [[ $CC_SUBJECT_CAPITALIZED == false || $CC_SUBJECT_CAPITALIZED == true ]] || CC_SUBJECT_CAPITALIZED=false
  [[ $CC_SUBJECT_NOT_PUNCTUATED == true || $CC_SUBJECT_NOT_PUNCTUATED == false ]] || CC_SUBJECT_NOT_PUNCTUATED=true

  local -a lines=()
  mapfile -t lines <"$message_file"
  local subject="${lines[0]:-}" second="${lines[1]:-}"
  local types_list
  types_list="$(
    IFS=,
    printf '%s' "${CC_ALLOWED_TYPES[*]}"
  )"

  local -a CC_VIOLATIONS=()

  if [[ -z $subject ]]; then
    __cog_cc_add_violation "empty-subject" "commit subject (first line) is empty" \
      "write 'type(scope): description'"
  elif [[ $subject != *:* ]]; then
    __cog_cc_add_violation "missing-separator" "subject has no 'type: ' separator" \
      "use 'type(scope): description', e.g. 'feat(api): add token refresh'"
  else
    local parsed before type scope desc
    parsed="$(cog::fn::git_parse_conventional_subject "$subject")"
    before="$(jq -r '.stem' <<<"$parsed")"
    type="$(jq -r '.type' <<<"$parsed")"
    scope="$(jq -r '.scope' <<<"$parsed")"
    desc="$(jq -r '.description' <<<"$parsed")"

    if [[ "$(jq -r '.space_after_colon' <<<"$parsed")" == false ]]; then
      __cog_cc_add_violation "missing-space-after-colon" "no space after the ':' separator" \
        "write 'type(scope): description' with one space after the colon"
    fi

    if [[ "$(jq -r '.scope_malformed' <<<"$parsed")" == true ]]; then
      __cog_cc_add_violation "bad-scope" "malformed scope in '${before}'" \
        "use 'type(scope): ...' with matching parens, e.g. 'fix(core/db): ...'"
    fi

    if ! __cog_cc_contains "$type" "${CC_ALLOWED_TYPES[@]}"; then
      __cog_cc_add_violation "unknown-type" "type '${type}' is not an allowed Conventional Commit type" \
        "use one of: ${types_list}"
    fi

    if [[ -n $scope ]]; then
      local -a segs=()
      IFS='/' read -ra segs <<<"$scope"
      local seg bad=0
      for seg in "${segs[@]}"; do
        [[ $seg =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || bad=1
      done
      ((bad == 0)) || __cog_cc_add_violation "bad-scope" "scope '${scope}' has an invalid segment" \
        "use '/'-separated segments of [A-Za-z0-9._-], e.g. 'module/sub-module'"
      if ((${#CC_ALLOWED_SCOPES[@]} > 0)) && ! __cog_cc_contains "$scope" "${CC_ALLOWED_SCOPES[@]}"; then
        __cog_cc_add_violation "disallowed-scope" "scope '${scope}' is not in the project's allowed_scopes" \
          "use one of the scopes configured in committed.toml"
      fi
    fi

    if [[ -z $desc ]]; then
      __cog_cc_add_violation "empty-description" "description after the type is empty" \
        "add a short imperative description, e.g. 'feat(api): add token refresh'"
    else
      if [[ $CC_SUBJECT_CAPITALIZED == false && $desc =~ ^[A-Z] ]]; then
        __cog_cc_add_violation "subject-capitalized" "description starts with an uppercase letter" \
          "lowercase the first word, e.g. 'add ...' not 'Add ...'"
      fi
      if [[ $CC_SUBJECT_NOT_PUNCTUATED == true && $desc == *. ]]; then
        __cog_cc_add_violation "subject-punctuated" "description ends with a period" \
          "drop the trailing '.'"
      fi
    fi

    if ((${#subject} > CC_LINE_LENGTH)); then
      local prefix="${subject% *}"
      [[ $prefix == "$subject" ]] && prefix=""
      ((${#prefix} > CC_LINE_LENGTH)) && __cog_cc_add_violation "subject-too-long" \
        "subject line is ${#subject} chars (limit ${CC_LINE_LENGTH})" \
        "tighten the subject to <= ${CC_LINE_LENGTH} chars; move detail to the body"
    fi
  fi

  if ((${#lines[@]} > 1)) && [[ -n $second ]]; then
    __cog_cc_add_violation "no-blank-before-body" "no blank line between subject and body" \
      "leave one empty line after the subject"
  fi

  local ok=true
  ((${#CC_VIOLATIONS[@]} == 0)) || ok=false
  jq -n \
    --argjson ok "$ok" \
    --argjson violations "$(cog::fn::git_json_object_array_from_lines "${CC_VIOLATIONS[@]}")" \
    '{ok: $ok, deferred: false, linter: null, config: null, violations: $violations}'
}

# Membership test (word equality) used by the commit-message validator.
__cog_cc_contains() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do
    [[ $item == "$needle" ]] && return 0
  done
  return 1
}
