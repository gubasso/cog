# shellcheck shell=bash
: 'desc: Deterministic PreToolUse/Stop hook decisions.'

__COG_HOOK_GUARD_CODEX_MIN_TIMEOUT_MS=600000

__cog_hook_guard_usage() {
  cat <<'EOF'
cog hook-guard — deterministic PreToolUse/Stop hook decisions

USAGE
  cog hook-guard codex-foreground            # PreToolUse(Bash)
  cog hook-guard prex-stop --owner-pid <pid> # Stop
  cog hook-guard --help

Both read the hook JSON payload on stdin and use the hook deny contract:
exit 2 + a human reason on stderr to BLOCK; exit 0 to allow.

codex-foreground
  Denies a Bash tool call whose command runs codex-session / codex-runner when
  it is backgrounded (run_in_background=true) or lacks a timeout of at least
  600000ms — the two ways a Codex child gets SIGTERM-reaped. Foreground,
  long-timeout, and all non-Codex Bash calls are allowed untouched.

prex-stop
  Blocks the owning session from stopping while a prex run's required artifacts
  are missing. Auto-cleans corrupt/orphaned locks. Resolves the lock directory
  and name from rundir_lock_dir/rundir_lock_name (the single source of truth),
  so it can never diverge from where rundir_lock_acquire writes the lock.

EXIT CODES
  0   allow (no block)
  2   block (hook deny contract)
  1   usage error
EOF
}

__cog_hook_guard_codex_foreground() {
  command -v jq >/dev/null || {
    printf 'hook-guard: jq is required\n' >&2
    exit 1
  }

  local payload cmd bg t
  payload="$(cat)"

  cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // ""' 2>/dev/null || printf '')"
  case "$cmd" in
    *codex-session* | *codex-runner*) ;;
    *) exit 0 ;;
  esac

  bg="$(printf '%s' "$payload" | jq -r '.tool_input.run_in_background // false' 2>/dev/null || printf 'false')"
  if [[ "$bg" == "true" ]]; then
    printf 'BLOCKED: never background a Codex call (run_in_background=true). Re-issue it in the FOREGROUND (omit run_in_background) with a Bash timeout of %sms. A backgrounded Codex child is SIGTERM-reaped when the turn ends — it loses all work and leaves a 0-byte runner JSON.\n' \
      "$__COG_HOOK_GUARD_CODEX_MIN_TIMEOUT_MS" >&2
    exit 2
  fi

  t="$(printf '%s' "$payload" | jq -r '.tool_input.timeout // empty' 2>/dev/null || printf '')"
  if [[ -z "$t" || ! "$t" =~ ^[0-9]+$ || "$t" -lt "$__COG_HOOK_GUARD_CODEX_MIN_TIMEOUT_MS" ]]; then
    printf 'BLOCKED: a Codex call needs a Bash timeout of at least %sms (got: %s). The default (~120000ms) SIGTERMs Codex mid-run. Re-issue this call with timeout: %s.\n' \
      "$__COG_HOOK_GUARD_CODEX_MIN_TIMEOUT_MS" "${t:-unset}" "$__COG_HOOK_GUARD_CODEX_MIN_TIMEOUT_MS" >&2
    exit 2
  fi

  exit 0
}

__cog_hook_guard_prex_stop() {
  local owner_pid=""
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --owner-pid)
        owner_pid="${2:-}"
        shift 2
        ;;
      *)
        __cog_hook_guard_usage >&2
        exit 1
        ;;
    esac
  done
  cat >/dev/null

  local lock_dir name
  lock_dir="$(cog::fn::rundir_lock_dir)"
  name="$(cog::fn::rundir_lock_name)"

  shopt -s nullglob
  local flags=("$lock_dir/$name"-*)
  ((${#flags[@]} > 0)) || exit 0

  local all_missing=()
  local flag run_dir op
  for flag in "${flags[@]}"; do
    [[ "$flag" == *.lock ]] || continue
    [[ -f "$flag" ]] || continue

    run_dir=""
    op=""
    {
      read -r run_dir
      read -r op
    } <"$flag" 2>/dev/null || true

    if [[ -z "$run_dir" || ! -d "$run_dir" ]]; then
      rm -f "$flag"
      continue
    fi
    if [[ -n "$op" ]] && ! kill -0 "$op" 2>/dev/null; then
      rm -f "$flag"
      continue
    fi
    if [[ -n "$op" && -n "$owner_pid" && "$op" != "$owner_pid" ]]; then
      continue
    fi

    local missing=()
    [[ -s "$run_dir/stage1-plan.txt" ]] || missing+=("Stage 1: Plan")
    [[ -s "$run_dir/stage2-reviewed-plan.md" ]] || missing+=("Stage 2: Reviewed plan")
    [[ -s "$run_dir/stage4-review.md" ]] || missing+=("Stage 4: Implementation review")
    if ((${#missing[@]} > 0)); then
      all_missing+=("$(IFS=', ' && printf '%s' "${flag##*/}: remaining — ${missing[*]}")")
    fi
  done

  if ((${#all_missing[@]} > 0)); then
    local joined
    joined="$(IFS='; ' && printf '%s' "${all_missing[*]}")"
    printf '{"decision":"block","reason":"prex workflow active in this session — %s. DO NOT delete the lock file; it belongs to this session'\''s running workflow."}' \
      "$joined" >&2
    exit 2
  fi

  exit 0
}

cog::cmd::hook_guard() {
  case "${1:-}" in
    codex-foreground)
      shift
      __cog_hook_guard_codex_foreground "$@"
      ;;
    prex-stop)
      shift
      __cog_hook_guard_prex_stop "$@"
      ;;
    -h | --help)
      __cog_hook_guard_usage
      exit 0
      ;;
    *)
      __cog_hook_guard_usage >&2
      exit 1
      ;;
  esac
}
