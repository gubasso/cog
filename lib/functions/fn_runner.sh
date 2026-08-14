# shellcheck shell=bash

# Provider-neutral runner mechanics, shared by every cog runner.
#
# What lives here carries nothing provider-shaped: artifact-path guards, the
# durable-job label derivation, launch working-directory resolution, and the
# run-directory snapshot and proof verbs. Every runner needs these verbatim, so
# a second copy would be a second thing to correct.
#
# What deliberately does NOT live here: argument-vector construction, effort and
# access spelling, precondition shape, resume identity, and status
# classification. The provider CLIs disagree on all of them, and a translation
# layer over that disagreement needs correcting on each provider release.
#
# Error messages take the runner name as their first argument so a hoisted guard
# still names the command the operator actually typed.

# Derive the durable-job label from the --state filename (strip .longrun.json).
cog::fn::runner::label_for_state() {
  local state_file="$1" base
  base="$(basename -- "$state_file")"
  base="${base%.longrun.json}"
  base="${base%.json}"
  printf '%s\n' "$base"
}

cog::fn::runner::bool_for_status() {
  [[ $1 == ok ]] && printf '%s\n' true || printf '%s\n' false
}

# Fail closed on a relative artifact path. A durable job launches from the
# project repo (see cog::fn::runner::resolve_cwd), so a relative --state /
# --output / --events / --stderr resolves against the project tree and scatters
# artifacts loose in it. Require an absolute path from a run dir instead.
cog::fn::runner::require_abs() {
  local runner="$1" option="$2" value="$3"
  # shellcheck disable=SC2016 # literal $RUN_DIR in the operator-facing hint, not an expansion
  [[ $value == /* ]] || cog::fn::error_raise "InvalidInput" \
    "${runner} artifact path must be absolute" "option: ${option}, path: ${value}" \
    "relative paths resolve against the job cwd (the project repo) and scatter artifacts into it" \
    'allocate RUN_DIR="$(cog rundir <prefix>)" and pass $RUN_DIR/<file>'
}

# Fail closed when two runner-owned artifact paths name the same file. The four
# paths are handed to cog::fn::longrun::start as independent sinks — the state
# file is replaced atomically, the events file receives the detached stdout
# stream, the stderr file receives the error stream, and the output file holds
# the agent's closing message. Aliasing any pair silently destroys one of them:
# --state equal to --output lets the closing-message write truncate the durable
# state, and --state equal to --events races the live stream against the atomic
# replacement. Absoluteness alone does not catch this, so compare normalized
# paths pairwise before anything durable exists.
cog::fn::runner::require_distinct_artifacts() {
  local runner="$1"
  shift
  local -a names=() paths=()
  local i j
  while (($# > 1)); do
    names+=("$1")
    paths+=("$(realpath -m -- "$2")")
    shift 2
  done
  for ((i = 0; i < ${#paths[@]}; i++)); do
    for ((j = i + 1; j < ${#paths[@]}; j++)); do
      [[ ${paths[i]} == "${paths[j]}" ]] || continue
      # shellcheck disable=SC2016 # literal $RUN_DIR in the operator-facing hint, not an expansion
      cog::fn::error_raise "InvalidInput" \
        "${runner} artifact paths must be distinct" \
        "options: ${names[i]} and ${names[j]}, path: ${paths[i]}" \
        "each runner artifact is an independent sink; sharing one path makes the writes clobber each other" \
        'give each artifact its own $RUN_DIR/<label>.<kind> path'
    done
  done
}

# Create the run directory that holds a runner's artifacts. The preflight
# fragment is the first thing written there, and it is written before the
# durable job exists, so without this a run-dir the caller has not yet created
# fails the preflight write instead of being created by the launcher.
cog::fn::runner::ensure_run_dir() {
  local runner="$1" run_dir="$2"
  mkdir -p -- "$run_dir" 2>/dev/null || cog::fn::error_raise "InvalidInput" \
    "${runner} could not create the run directory" "path: ${run_dir}" \
    "" "check the --state path and its permissions"
}

cog::fn::runner::require_state() {
  local runner="$1" state="$2"
  [[ -n $state ]] || cog::fn::error_raise "MissingArgument" \
    "missing --state" "option: --state" "" "run 'cog ${runner} --help'"
  [[ -r $state ]] || cog::fn::error_raise "InputNotFound" \
    "${runner} job state not found" "path: ${state}" "" "check the --state path"
}

# Extract every artifact-write target a prompt references via a --output flag.
# A prompt may embed an instruction like `$plan-oneshot --output <RUN_DIR>/prepared-plan.md`
# (the inner agent then runs `cog plan-doc save --output <RUN_DIR>/prepared-plan.md`); the
# collision key is always the --output value, so one regex covers both spellings.
# Backslash-continued lines are folded first so a flag split across lines still resolves.
# Angle-bracket <placeholder> tokens are dropped; nothing is eval'd, so a literal $VAR
# stays literal — no expansion, no injection, no false positive from a `$VAR` mention.
cog::fn::runner::extract_prompt_targets() {
  local prompt_file="$1" folded line rest path re
  re='--output[[:space:]]+"?([^[:space:]"'"'"']+)'
  folded="$(sed -e ':a' -e '/\\$/{N;s/\\\n//;ba}' "$prompt_file")"
  while IFS= read -r line; do
    rest="$line"
    while [[ $rest =~ $re ]]; do
      path="${BASH_REMATCH[1]}"
      rest="${rest#*"${BASH_REMATCH[0]}"}"
      case "$path" in
        '<'*) continue ;;
      esac
      printf '%s\n' "$path"
    done
  done <<<"$folded"
}

# Fail closed before launch when the runner's own --output equals an artifact the
# prompt tells the inner agent to write. The runner --output holds the agent's
# closing message — written by the provider (codex --output-last-message) or by
# the runner itself from the event stream (claude) — so if that path is also
# where an embedded plan/artifact write lands, the closing message clobbers the
# durable artifact. Compare on exact absolute-path equality (realpath -m
# normalizes .././dup-slashes without requiring existence) so an unrelated
# --output mentioned in the brief never trips it. An unreadable prompt defers to
# the downstream prompt-readable check in the provider layer.
cog::fn::runner::guard_output_collision() {
  local runner="$1" output="$2" prompt="$3" target output_abs target_abs provider
  [[ -r $prompt ]] || return 0
  # The hint names the provider so it reads as the file the operator would
  # actually write: codex-runner -> <label>-codex-output.md.
  provider="${runner%-runner}"
  output_abs="$(realpath -m -- "$output")"
  while IFS= read -r target; do
    [[ -n $target ]] || continue
    target_abs="$(realpath -m -- "$target")"
    [[ $output_abs == "$target_abs" ]] || continue
    # shellcheck disable=SC2016 # literal $RUN_DIR in the operator-facing hint, not an expansion
    cog::fn::error_raise "InvalidInput" \
      "${runner} --output collides with a prompt artifact-write target" \
      "path: ${output}" \
      "the runner --output captures the agent's closing message and would clobber the artifact the prompt writes there" \
      "route the last-message capture to a distinct \$RUN_DIR/<label>-${provider}-output.md"
  done < <(cog::fn::runner::extract_prompt_targets "$prompt")
}

# Resolve the durable-job working directory. A provider CLI may refuse to run
# outside a trusted directory (codex exec does), so the job must launch from the
# project repo rather than the scratch RUN_DIR the observer may be sitting in.
# An explicit --cwd wins; otherwise resolve the git repo root of $PWD; otherwise
# keep $PWD.
cog::fn::runner::resolve_cwd() {
  local cwd="${1:-}"
  if [[ -z $cwd ]]; then
    cwd="$(cog::fn::git_root_for "$PWD" 2>/dev/null || true)"
    [[ -n $cwd ]] || cwd="$PWD"
  fi
  printf '%s\n' "$cwd"
}

cog::fn::runner::json_array() {
  if (($# == 0)); then
    jq -cn '[]'
  else
    printf '%s\n' "$@" | jq -R . | jq -s .
  fi
}

cog::fn::runner::snapshot_pre_json() {
  [[ $# -eq 2 ]] || cog::fn::error_raise "MissingArgument" \
    "invalid snapshot-pre arguments" "usage: snapshot-pre <run-dir> <out.snap>" "" ""
  cog::fn::rundir_snapshot "$1" "$2"
  jq -n --arg action snapshot-pre --argjson ok true --arg run_dir "$1" --arg snapshot "$2" \
    '{action: $action, ok: $ok, run_dir: $run_dir, snapshot: $snapshot}'
}

cog::fn::runner::snapshot_post_json() {
  [[ $# -eq 4 ]] || cog::fn::error_raise "MissingArgument" \
    "invalid snapshot-post arguments" "usage: snapshot-post <run-dir> <pre.snap> <post.snap> <diff>" "" ""
  cog::fn::rundir_snapshot "$1" "$3"
  cog::fn::rundir_snapshot_diff "$2" "$3" "$4"
  jq -n --arg action snapshot-post --argjson ok true --arg run_dir "$1" --arg pre "$2" --arg post "$3" --arg diff "$4" \
    '{action: $action, ok: $ok, run_dir: $run_dir, pre_snapshot: $pre, post_snapshot: $post, diff: $diff}'
}

# Verify that a delegation actually produced what it claimed: every named
# artifact is non-empty, the run-directory proof diff is non-empty, and the last
# artifact satisfies an optional jq predicate.
cog::fn::runner::verify_proof_json() {
  local runner="$1" proof="" require_json="" ok=true reason="" last=""
  local -a artifacts=() reasons=()
  shift
  while (($# > 0)); do
    case "$1" in
      --proof)
        proof="${2:-}"
        shift 2
        ;;
      --artifact)
        artifacts+=("${2:-}")
        shift 2
        ;;
      --require-json)
        require_json="${2:-}"
        shift 2
        ;;
      *) cog::fn::error_raise "InvalidInput" "invalid verify-proof argument" "argument: $1" "" "run 'cog ${runner} --help'" ;;
    esac
  done
  [[ -n $proof && ${#artifacts[@]} -ge 1 ]] || cog::fn::error_raise "MissingArgument" \
    "missing verify-proof argument" "usage: cog ${runner} verify-proof --proof <diff> --artifact <file>" "" ""
  local artifact
  for artifact in "${artifacts[@]}"; do
    [[ -n $artifact ]] || cog::fn::error_raise "MissingArgument" "empty artifact path" "option: --artifact" "" ""
    [[ -s $artifact ]] || reasons+=("missing or empty artifact: $artifact")
  done
  [[ -s $proof ]] || reasons+=("missing or empty proof diff: $proof")
  if [[ -n $require_json ]]; then
    last="${artifacts[${#artifacts[@]} - 1]}"
    if [[ -s $last ]]; then
      jq -e "$require_json" "$last" >/dev/null 2>&1 || reasons+=("artifact failed json check ($require_json): $last")
    fi
  fi
  if ((${#reasons[@]} > 0)); then
    ok=false
    reason="$(printf '%s; ' "${reasons[@]}")"
    reason="${reason%; }"
  fi
  jq -n \
    --arg action verify-proof \
    --argjson ok "$ok" \
    --arg reason "$reason" \
    --argjson artifacts "$(cog::fn::runner::json_array "${artifacts[@]}")" \
    --arg proof "$proof" \
    '{action: $action, ok: $ok, reason: (if $reason == "" then null else $reason end),
      artifacts: $artifacts, proof: $proof}'
}
