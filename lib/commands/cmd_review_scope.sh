# shellcheck shell=bash
: 'desc: Detect changed-file review scope.'

__cog_review_scope_self_check='.repo_root != null and (.changed_files | type == "array") and (.staged_files | type == "array") and (.unstaged_files | type == "array") and (.status_files | type == "array") and (.commit_files | type == "array") and (.requested_files | type == "array") and (.commits | type == "array") and (.declaration | type == "object") and (.diff_stats | type == "object")'

__cog_review_scope_usage() {
  cog::fn::ui_data "Usage: cog review-scope [--declaration <scope.json>] (<out.json>|--json)"
  cog::fn::ui_data "Usage: cog review-scope check [--max-files <n>] [--max-lines <n>] [--declaration <scope.json>] [--json]"
}

# What to review arrives as one declaration, never as a set of flags. Choosing
# the sources is judgment that belongs to the caller holding the session;
# resolving them to files and lines is the mechanics that belong here. A flag
# per source kind mirrored the same four fields the review-loop handoff already
# carried, so one concept had two spellings and every new source kind would have
# had to be added to both. See lib/functions/fn_scope_declaration.sh.
__cog_review_scope_take_declaration() {
  local -n __cog_scope_decl_path="$1"
  shift

  [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" \
    "missing scope declaration path" "option: $1" "" \
    "pass a declaration file, e.g. --declaration scope.json"
  [[ -z $__cog_scope_decl_path ]] || cog::fn::error_raise "InvalidInput" \
    "duplicate scope declaration" "option: $1" "" "pass --declaration once"
  __cog_scope_decl_path="$2"
}

__cog_review_scope_check_self_check='(.schema=="cog.review-scope.check.v1") and (.ok|type=="boolean") and (.exceeded|type=="boolean") and (.actual|type=="object") and (.breaches|type=="array")'

__cog_review_scope_check_build_json() {
  local max_files="$1" max_lines="$2" declaration="${3:-}" scope_json files lines
  # Measure the same changeset the review will read, so the guard cannot pass a
  # diff the reviewer then chokes on. With no declaration that is the whole
  # working tree (staged, unstaged, and untracked), which catches a runaway diff
  # before commit, when a round's edits are typically still unstaged.
  #
  # A declared file contributes to the file count but not the line count: a bare
  # path listing carries no diff. A file touched both in a commit selector and
  # in the working tree is one entry in changed_files but is counted twice in
  # lines, which is right — those are two distinct sets of lines to read.
  scope_json="$(__cog_review_scope_build_json "$declaration")"
  files="$(jq '.changed_files | length' <<<"$scope_json")"
  lines="$(jq '[.diff_stats.staged.files[], .diff_stats.unstaged.files[], .diff_stats.commits.files[] | .added + .deleted] | add // 0' <<<"$scope_json")"
  jq -n \
    --argjson files "$files" \
    --argjson lines "$lines" \
    --arg max_files "$max_files" \
    --arg max_lines "$max_lines" \
    '
    ($max_files | if . == "" then null else tonumber end) as $mf
    | ($max_lines | if . == "" then null else tonumber end) as $ml
    | ([ (if ($mf != null and $files > $mf) then "files" else empty end),
        (if ($ml != null and $lines > $ml) then "lines" else empty end) ]) as $breaches
    | {
        schema: "cog.review-scope.check.v1",
        ok: (($breaches | length) == 0),
        exceeded: (($breaches | length) > 0),
        declared: {max_files: $mf, max_lines: $ml},
        actual: {files: $files, lines: $lines},
        breaches: $breaches
      }'
}

__cog_review_scope_check_cmd() {
  local max_files="" max_lines="" mode="" out="" json declaration=""
  while (($# > 0)); do
    case "$1" in
      --declaration)
        __cog_review_scope_take_declaration declaration "$@"
        shift 2
        continue
        ;;
      -h | --help)
        __cog_review_scope_usage
        return 0
        ;;
      --max-files)
        [[ $# -ge 2 && ${2:-} =~ ^[0-9]+$ ]] || cog::fn::error_raise "InvalidInput" \
          "max-files must be a non-negative integer" "option: --max-files" "value: ${2:-}" \
          "run 'cog review-scope --help'"
        max_files="$2"
        shift 2
        ;;
      --max-lines)
        [[ $# -ge 2 && ${2:-} =~ ^[0-9]+$ ]] || cog::fn::error_raise "InvalidInput" \
          "max-lines must be a non-negative integer" "option: --max-lines" "value: ${2:-}" \
          "run 'cog review-scope --help'"
        max_lines="$2"
        shift 2
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" \
          "duplicate review-scope check output mode" "" "" "choose either --json or an output path"
        mode="json"
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown review-scope check option" "option: $1" "" "run 'cog review-scope --help'"
        ;;
      *)
        [[ -z $out ]] || cog::fn::error_raise "TooManyArguments" \
          "too many review-scope check output paths" "argument: $1" "" "run 'cog review-scope --help'"
        out="$1"
        [[ -n $mode ]] || mode="file"
        shift
        ;;
    esac
  done

  [[ -n $max_files || -n $max_lines ]] || cog::fn::error_raise "MissingArgument" \
    "missing scope limit" "usage: cog review-scope check [--max-files <n>] [--max-lines <n>]" "" \
    "declare at least one of --max-files or --max-lines"
  [[ -n $mode || ${COG_UI_JSON:-false} != true ]] || mode=json
  [[ -n $mode ]] || mode=json

  json="$(__cog_review_scope_check_build_json "$max_files" "$max_lines" "$declaration")"
  if [[ $mode == file ]]; then
    cog::fn::json_write_fragment "$out" "$__cog_review_scope_check_self_check" "$json"
  else
    cog::fn::json_emit "$__cog_review_scope_check_self_check" "$json"
  fi
  jq -e '.exceeded == false' <<<"$json" >/dev/null
}

# The commit and requested sets default to empty so the three-argument
# working-tree call this started as still means exactly what it meant.
__cog_review_scope_changed_files() {
  local staged="$1"
  local unstaged="$2"
  local status_files="$3"
  local commit_files="${4:-[]}"
  local requested_files="${5:-[]}"
  jq -cn \
    --argjson staged "$staged" \
    --argjson unstaged "$unstaged" \
    --argjson status_files "$status_files" \
    --argjson commit_files "$commit_files" \
    --argjson requested_files "$requested_files" \
    '($staged + $unstaged + ($status_files | map(select(.untracked) | .path))
      + $commit_files + $requested_files) | unique'
}

# Resolve the commits the selectors name, as the union over each selector taken
# on its own. cog::fn::git_log_range_json hands every range to one revision walk,
# where two ranges intersect as `^A B ^C D` and drop a commit that one of them
# does include — while the file and stat helpers above diff each range
# separately and do include it. Walking per range is what keeps `commits[]` the
# same set that `commit_files` was built from, which matters because the skills
# pin later rounds to the SHAs reported here. A three-dot range is walked as a
# two-dot one for the same reason, see below. SHAs are already `--no-walk`, so
# they go in one call.
__cog_review_scope_commits() {
  local -a per_selector=()
  local -a shas=()
  local commits

  local walk
  while (($# > 0)); do
    case "$1" in
      --range)
        # `git diff A...B` shows the merge base against B — B's side only —
        # while a history walk reads `A...B` as the symmetric difference and
        # returns A's unique commits too. Reported as-is, commits[] would name
        # commits whose files commit_files never counted, and pinning those SHAs
        # in a later round would widen the subject. Walking `A..B` is the history
        # that matches what `git diff A...B` actually diffed.
        walk="$2"
        case "$walk" in
          *"..."*) walk="${walk%%"..."*}..${walk#*"..."}" ;;
        esac
        per_selector+=("$(cog::fn::git_log_range_json --range "$walk")")
        shift 2
        ;;
      --sha)
        shas+=(--sha "$2")
        shift 2
        ;;
      *) shift ;;
    esac
  done
  ((${#shas[@]} == 0)) || per_selector+=("$(cog::fn::git_log_range_json "${shas[@]}")")

  commits="$(printf '%s\n' "${per_selector[@]}" \
    | jq -sc 'add // [] | reduce .[] as $c ([]; if any(.[]; .sha == $c.sha) then . else . + [$c] end)')"
  jq -c 'map({sha, short, subject})' <<<"$commits"
}

# Resolve a range's endpoints to commit hashes, returning the rewritten range
# through the caller's variable. Same reason the SHA selectors are resolved once:
# `A..B` names whatever A and B point at *at the time of the call*, and the three
# collectors are three separate git invocations, so a branch that moves between
# them would leave commit_files describing one range while diff_stats.commits and
# commits[] describe another. Rewriting to hashes also keeps a resumed round
# pinned to the subject round 1 actually reviewed.
#
# The result comes back by name rather than on stdout because a die inside a
# command substitution is swallowed by an array append, and an unresolvable
# endpoint has to fail loudly rather than silently shrink the changeset.
# `A...B` keeps its three-dot form, so the merge-base semantics git gives it are
# preserved.
#
# A delimiter-free value is refused rather than passed through. `git diff HEAD`
# compares the working tree against that commit, so `--no-worktree --range HEAD`
# would pull the live tree back into a scope that just declared it out, while
# `git log HEAD` walks all of history — the three collectors would describe
# three different changesets. A single commit is what `--sha` is for.
__cog_review_scope_resolve_range() {
  local -n __cog_scope_range_out="$1"
  local range="$2" sep left right
  local -a ends=()

  case "$range" in
    *"..."*) sep="..." ;;
    *".."*) sep=".." ;;
    *)
      cog::fn::error_raise "InvalidInput" \
        "review-scope range needs a .. or ... separator" "option: --range ${range}" \
        "a bare commit diffs against the working tree and walks all history" \
        "write a range like A..B, or pass a single commit with --sha"
      ;;
  esac

  left="${range%%"${sep}"*}"
  right="${range#*"${sep}"}"
  # More than one separator would leave a `..` stranded inside an endpoint,
  # where it silently becomes part of a ref name git cannot resolve.
  case "${left}${right}" in
    *".."*)
      cog::fn::error_raise "InvalidInput" \
        "review-scope range has more than one separator" "option: --range ${range}" "" \
        "pass one range per --range, like A..B"
      ;;
  esac
  # An omitted endpoint means HEAD to git; spell that out so it is resolved
  # once here too rather than re-read per collector.
  ends=("${left:-HEAD}" "${right:-HEAD}")
  cog::fn::git_peel_commit_selectors ends ""
  __cog_scope_range_out="${ends[0]}${sep}${ends[1]}"
}

# Resolve one scope declaration into the review scope. The declared sources are
# additive: the live working tree, the commits named by `ranges` and `shas`, and
# the paths listed in `files`. With no declaration this resolves the working
# tree and issues exactly the git commands it always has, in the same order,
# because the commit helpers return early before invoking git.
#
# The declaration is validated by the shared schema before anything here runs,
# so this function never has to decide what a malformed source means. The
# source-less case is refused there too, at the point the declaration is
# written, rather than here at the point it is resolved.
__cog_review_scope_build_json() {
  local declaration_path="${1:-}"
  local repo_root branch staged_files unstaged_files status_json status_files
  local staged_stat unstaged_stat commit_scope commit_files commit_stat commits requested_files changed_files
  local declaration worktree selector resolved_range=""
  local -a ranges=() shas=() peeled_shas=() selectors=()

  if [[ -n $declaration_path ]]; then
    declaration="$(cog::fn::scope_declaration_read "$declaration_path")"
  else
    declaration="$(cog::fn::scope_declaration_default)"
  fi
  worktree="$(jq -r '.worktree' <<<"$declaration")"
  mapfile -t ranges < <(jq -r '.ranges[]' <<<"$declaration")
  mapfile -t shas < <(jq -r '.shas[]' <<<"$declaration")

  repo_root="$(cog::fn::git_root)" || cog::fn::error_raise "InputNotFound" \
    "could not resolve git repository root" "command: git rev-parse --show-toplevel" "" \
    "run from inside a git work tree"
  branch="$(cog::fn::git_current_branch)"

  # Resolve every commit selector once, here, and hand the resolved hashes to all
  # three collectors below. A branch or tag can move between two git calls, and
  # the collectors run as three separate invocations: resolving per collector
  # would let commit_files describe one commit while diff_stats.commits and
  # commits[] describe another, an internally inconsistent scope. The original
  # selector strings are kept for `sources.ranges` and `sources.shas`, which
  # report what the caller asked for rather than what it resolved to.
  peeled_shas=("${shas[@]}")
  ((${#peeled_shas[@]} == 0)) || cog::fn::git_peel_commit_selectors peeled_shas ""
  for selector in "${ranges[@]}"; do
    __cog_review_scope_resolve_range resolved_range "$selector"
    selectors+=(--range "$resolved_range")
  done
  for selector in "${peeled_shas[@]}"; do
    selectors+=(--sha "$selector")
  done

  if [[ $worktree == true ]]; then
    staged_files="$(cog::fn::git_staged_files_json)"
    unstaged_files="$(cog::fn::git_unstaged_files_json)"
    status_json="$(cog::fn::git_status_json)"
    status_files="$(jq -c '.files' <<<"$status_json")"
    staged_stat="$(cog::fn::git_diff_stat_json --staged)"
    unstaged_stat="$(cog::fn::git_diff_stat_json --unstaged)"
  else
    staged_files='[]'
    unstaged_files='[]'
    status_files='[]'
    staged_stat='{"mode":"staged","files":[]}'
    unstaged_stat='{"mode":"unstaged","files":[]}'
  fi

  # One call, both answers: the file list and the line stats are two readings of
  # a single numstat record set, so they cannot describe different diffs.
  commit_scope="$(cog::fn::git_range_scope_json "${selectors[@]}")"
  commit_files="$(jq -c '.files' <<<"$commit_scope")"
  commit_stat="$(jq -c '.stat' <<<"$commit_scope")"
  commits="$(__cog_review_scope_commits "${selectors[@]}")"
  requested_files="$(jq -c '.files' <<<"$declaration")"
  changed_files="$(__cog_review_scope_changed_files \
    "$staged_files" "$unstaged_files" "$status_files" "$commit_files" "$requested_files")"

  # A declared source that resolves to nothing lands here as an empty scope,
  # which every consumer reads as "nothing to review" — the same false clean the
  # no-source refusal above exists to prevent, arrived at one step later. The
  # exemption is narrow and deliberate: only a working-tree-*only* run may come
  # back empty, because a clean tree legitimately has nothing to review and the
  # skills already own that stop condition. Once the caller has named a commit
  # or a file list, an empty union means the thing they asked to review was not
  # found, and the worktree flag does not make that any less of a false clean.
  [[ $worktree == true && ${#ranges[@]} -eq 0 && ${#shas[@]} -eq 0 && $requested_files == "[]" ]] \
    || [[ $changed_files != "[]" ]] \
    || cog::fn::error_raise "InvalidInput" \
      "review-scope resolved to an empty scope" "declaration: ${declaration}" \
      "the declared sources matched no files" \
      "check the commit refs and the file list, or let the working tree back in"

  jq -n \
    --arg repo_root "$repo_root" \
    --arg branch "$branch" \
    --argjson changed_files "$changed_files" \
    --argjson staged_files "$staged_files" \
    --argjson unstaged_files "$unstaged_files" \
    --argjson status_files "$status_files" \
    --argjson commit_files "$commit_files" \
    --argjson requested_files "$requested_files" \
    --argjson commits "$commits" \
    --argjson declaration "$declaration" \
    --argjson staged_stat "$staged_stat" \
    --argjson unstaged_stat "$unstaged_stat" \
    --argjson commit_stat "$commit_stat" \
    '{
      repo_root: $repo_root,
      branch: $branch,
      changed_files: $changed_files,
      staged_files: $staged_files,
      unstaged_files: $unstaged_files,
      status_files: $status_files,
      commit_files: $commit_files,
      requested_files: $requested_files,
      commits: $commits,
      declaration: $declaration,
      diff_stats: {
        staged: $staged_stat,
        unstaged: $unstaged_stat,
        commits: $commit_stat
      }
    }'
}

cog::cmd::review_scope() {
  local mode="" out="" json declaration=""

  if [[ ${1:-} == check ]]; then
    shift
    __cog_review_scope_check_cmd "$@"
    return
  fi

  while (($# > 0)); do
    case "$1" in
      --declaration)
        __cog_review_scope_take_declaration declaration "$@"
        shift 2
        continue
        ;;
      -h | --help)
        __cog_review_scope_usage
        return 0
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" \
          "duplicate review-scope output mode" "" "" "choose either --json or an output path"
        mode="json"
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown review-scope option" "option: $1" "" "run 'cog review-scope --help'"
        ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise "TooManyArguments" \
          "too many review-scope output paths" "argument: $1" "" "run 'cog review-scope --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done

  [[ -n $mode || ${COG_UI_JSON:-false} != true ]] || mode=json
  [[ -n $mode ]] || cog::fn::error_raise "MissingArgument" \
    "missing review-scope output mode" "usage: cog review-scope (<out.json>|--json)" "" \
    "run 'cog review-scope --help'"

  json="$(__cog_review_scope_build_json "$declaration")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$__cog_review_scope_self_check" "$json"
  else
    cog::fn::json_write_fragment "$out" "$__cog_review_scope_self_check" "$json"
  fi
}
