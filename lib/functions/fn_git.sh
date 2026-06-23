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
    local before="${subject%%:*}" after="${subject#*:}"
    local desc

    if [[ -z $after ]]; then
      desc=""
    elif [[ $after == " "* ]]; then
      desc="${after# }"
    else
      desc="$after"
      __cog_cc_add_violation "missing-space-after-colon" "no space after the ':' separator" \
        "write 'type(scope): description' with one space after the colon"
    fi

    # Strip an optional breaking-change '!' before parsing the scope.
    [[ $before == *"!" ]] && before="${before%!}"

    local type="$before" scope=""
    if [[ $before == *"("* || $before == *")"* ]]; then
      if [[ $before =~ ^([A-Za-z0-9_-]+)\((.+)\)$ ]]; then
        type="${BASH_REMATCH[1]}"
        scope="${BASH_REMATCH[2]}"
      else
        type="${before%%(*}"
        __cog_cc_add_violation "bad-scope" "malformed scope in '${before}'" \
          "use 'type(scope): ...' with matching parens, e.g. 'fix(core/db): ...'"
      fi
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
    --argjson violations "$(__cog_git_json_object_array_from_lines "${CC_VIOLATIONS[@]}")" \
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
