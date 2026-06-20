# shellcheck shell=bash
: 'desc: Deterministic Stop hook decisions for active workflows.'

__cog_hook_guard_usage() {
  cat <<'EOF'
cog hook-guard — deterministic Stop hook decisions for active workflows

USAGE
  cog hook-guard executor-prex-stop --owner-pid <pid> # Stop
  cog hook-guard prex-stop --owner-pid <pid> # Stop
  cog hook-guard --help

Reads the hook JSON payload on stdin and uses the hook deny contract:
exit 2 + a human reason on stderr to BLOCK; exit 0 to allow.

executor-prex-stop, prex-stop
  Blocks the owning session from stopping while an executor-prex/prex run's
  required artifacts are missing. Auto-cleans corrupt/orphaned locks. Resolves
  the lock directory and name from rundir_lock_dir/rundir_lock_name (the single
  source of truth), so it can never diverge from where rundir_lock_acquire
  writes the lock.

EXIT CODES
  0   allow (no block)
  2   block (hook deny contract)
  1   usage error
EOF
}

__cog_hook_guard_prex_stop() {
  local owner_pid=""
  while [[ $# -gt 0 ]]; do
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
    [[ $flag == *.lock ]] || continue
    [[ -f $flag ]] || continue

    run_dir=""
    op=""
    {
      read -r run_dir
      read -r op
    } <"$flag" 2>/dev/null || true

    if [[ -z $run_dir || ! -d $run_dir ]]; then
      rm -f "$flag"
      continue
    fi
    if [[ -n $op ]] && ! kill -0 "$op" 2>/dev/null; then
      rm -f "$flag"
      continue
    fi
    if [[ -n $op && -n $owner_pid && $op != "$owner_pid" ]]; then
      continue
    fi

    local missing=()
    [[ -s "$run_dir/stage1-plan.txt" ]] || missing+=("Stage 1: Plan")
    [[ -s "$run_dir/stage2-reviewed-plan.md" ]] || missing+=("Stage 2: Reviewed plan")
    [[ -s "$run_dir/stage3-impl-report.txt" ]] || missing+=("Stage 3: Implementation report")
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
    executor-prex-stop | prex-stop)
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
