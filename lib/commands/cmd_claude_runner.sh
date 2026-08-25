# shellcheck shell=bash
: 'desc: Run claude-session orchestration helpers.'

# The Codex-to-Claude lane. This is the mirror of codex-runner: a Codex host
# drives it with the same $? branch a Claude host uses today, because the exit
# protocol is the durable-job layer's, not either provider's — 0 done ok,
# 1 done failed, 75 still running.
#
# The verb set is deliberately smaller than codex-runner's. There is no resume
# verb yet: resume identity is spelled differently on each provider and nothing
# calls for a warm Claude round.

__cog_claude_runner_self_check='.action != null and .ok != null'

__cog_claude_runner_usage() {
  cog::fn::ui_data "Usage: cog claude-runner run-exec [--access <read-only|write>] --effort <tier> [--account <name>] [--profile <name>] --prompt <file> --output <file> --events <file> --state <file> [--stderr <file>]"
  cog::fn::ui_data "Usage: cog claude-runner finalize --state <file> [--max-wall <secs>]"
  cog::fn::ui_data "Usage: cog claude-runner gate <out.json>"
}

# Check the launch preconditions and fail before anything durable exists.
#
# ADR-0031: the wrapper execs its child, so once a job exists its status belongs
# to the agent and nothing can tell a missing credential apart from a legal
# agent exit. Running this before longrun::start is what keeps the artifact-only
# classification rule meaning one thing. A failure here costs no durable job and
# no state file; the preflight fragment it wrote stays behind deliberately, as
# the artifact the operator reads to see which precondition failed.
__cog_claude_runner_preflight() {
  local out="$1"
  local available health auth

  if ! declare -F __cog_preflight_claude >/dev/null; then
    # shellcheck source=/dev/null
    source "${LIB_DIR}/commands/cmd_preflight.sh"
  fi
  __cog_preflight_claude "$out" >/dev/null

  available="$(jq -r '.claude_session.available' "$out")"
  [[ $available == true ]] || cog::fn::error_raise "InvalidInput" \
    "claude-session is not available on PATH" "binary: $(cog::fn::claude_binary)" \
    "" "install the claude session wrapper or add it to PATH"
  health="$(jq -r '.claude_session.health' "$out")"
  [[ $health == ok ]] || cog::fn::error_raise "InvalidInput" \
    "claude-session is not healthy" "health: ${health}" \
    "the wrapper is present but did not report a version" "check the claude-session installation"
  auth="$(jq -r '.claude_session.auth' "$out")"
  [[ $auth == ok ]] || cog::fn::error_raise "InvalidInput" \
    "no bound claude-session account" "auth: ${auth}" \
    "reporting a precondition is diagnosis; satisfying one is account management" \
    "bind an account with 'claude-session-rs account bind' and retry"
}

# run-exec is a non-blocking LAUNCHER. Claude runs as a cog-owned durable job
# (detached in its own session) so a Bash-tool 600s SIGTERM cannot kill it.
# The result JSON is produced later by `finalize`, reconstructed from durable
# artifacts; this call only starts the job and prints STATE_FILE=/JOB_PGID=.
__cog_claude_runner_run_exec() {
  local access="read-only" effort="" model="" account="" profile=""
  local prompt="" output="" events="" stderr="" state="" cwd=""
  local command label run_dir engine_meta pgid
  local -a argv=()
  while (($# > 0)); do
    case "$1" in
      --access)
        access="${2:-}"
        shift 2
        ;;
      --effort)
        effort="${2:-}"
        shift 2
        ;;
      --account)
        account="${2:-}"
        shift 2
        ;;
      --profile)
        profile="${2:-}"
        shift 2
        ;;
      --prompt)
        prompt="${2:-}"
        shift 2
        ;;
      --output)
        output="${2:-}"
        shift 2
        ;;
      --events)
        events="${2:-}"
        shift 2
        ;;
      --stderr)
        stderr="${2:-}"
        shift 2
        ;;
      --state)
        state="${2:-}"
        shift 2
        ;;
      *) cog::fn::error_raise "InvalidInput" "invalid run-exec argument" "argument: $1" "" "run 'cog claude-runner --help'" ;;
    esac
  done
  [[ -n $effort && -n $prompt && -n $output && -n $events ]] || cog::fn::error_raise "MissingArgument" \
    "missing run-exec argument" "usage: cog claude-runner run-exec [--access <read-only|write>] --effort <tier> --prompt <file> --output <file> --events <file> --state <file>" "" \
    "run 'cog claude-runner --help'"
  case "$access" in
    read-only | write) ;;
    *) cog::fn::error_raise "InvalidInput" "invalid run-exec access" "access: ${access}" "expected read-only or write" "" ;;
  esac

  command="$(cog::fn::claude_exec_command "$account" "$profile" "$access" "$effort" "$model" "$prompt" "$events" "$stderr")"
  [[ -n $state ]] || cog::fn::error_raise "MissingArgument" \
    "missing --state" "option: --state" "every claude run is a durable job" "pass --state <run-dir>/<label>.longrun.json"
  label="$(cog::fn::runner::label_for_state "$state")"
  run_dir="$(dirname -- "$state")"
  [[ -n $stderr ]] || stderr="${run_dir}/${label}.stderr.log"

  cog::fn::runner::require_abs claude-runner --state "$state"
  cog::fn::runner::require_abs claude-runner --output "$output"
  cog::fn::runner::require_abs claude-runner --events "$events"
  cog::fn::runner::require_abs claude-runner --stderr "$stderr"

  cog::fn::runner::require_distinct_artifacts claude-runner \
    --state "$state" --output "$output" --events "$events" --stderr "$stderr"

  cog::fn::runner::guard_output_collision claude-runner "$output" "$prompt"

  # Preconditions before the durable job, per ADR-0031. Everything above this
  # line is argument shape; nothing durable exists yet, and nothing will if this
  # raises.
  cog::fn::runner::ensure_run_dir claude-runner "$run_dir"
  __cog_claude_runner_preflight "${run_dir}/${label}.preflight.json"

  cwd="$(cog::fn::runner::resolve_cwd "$cwd")"

  cog::fn::claude_exec_argv "$account" "$profile" "$access" "$effort" "$model" "$prompt" argv
  engine_meta="$(jq -cn \
    --arg engine_action run-exec --arg access "$access" --arg effort "$effort" \
    --arg model "$model" --arg account "$account" --arg profile "$profile" --arg command "$command" \
    '{engine_action: $engine_action, access: $access, effort: $effort, model: $model,
      account: $account, profile: $profile, command: $command}')"

  cog::fn::longrun::start --state "$state" --label "$label" --cwd "$cwd" \
    --stdout "$events" --stderr "$stderr" --output "$output" \
    --engine claude --engine-meta "$engine_meta" -- "${argv[@]}"
  pgid="$(jq -r '.pgid' "$state" 2>/dev/null || true)"
  cog::fn::ui_data "STATE_FILE=${state}"
  cog::fn::ui_data "JOB_PGID=${pgid}"
}

# Classify a finished (or lost) claude job from durable artifacts. Safe to call
# even if the launching observer was killed: nothing here depends on it.
__cog_claude_runner_finalize() {
  local state="" max_wall=0 poll=3
  while (($# > 0)); do
    case "$1" in
      --state)
        state="${2:-}"
        shift 2
        ;;
      --max-wall)
        max_wall="${2:-}"
        shift 2
        ;;
      *) cog::fn::error_raise "InvalidInput" "invalid finalize argument" "argument: $1" "" "run 'cog claude-runner --help'" ;;
    esac
  done
  cog::fn::runner::require_state claude-runner "$state"
  [[ $max_wall =~ ^[0-9]+$ ]] || max_wall=0

  ((max_wall > 0)) && cog::fn::longrun::wait "$state" "$max_wall" "$poll" >/dev/null

  local resolve base exit_code exit_source
  resolve="$(cog::fn::longrun::resolve_exit "$state")"
  base="$(jq -r '.state' <<<"$resolve")"
  exit_code="$(jq -r '.exit_code // ""' <<<"$resolve")"
  exit_source="$(jq -r '.exit_source // ""' <<<"$resolve")"

  if [[ $base == running ]]; then
    # Not terminal yet. Never classify a live job (its event stream is
    # mid-write, so the result envelope may not have arrived).
    # GR4: signal "still running" via exit 75; the caller simply re-runs finalize.
    cog::fn::json_emit '(.state | type == "string")' "$(jq -c '. + {ok: false}' "$state")"
    cog::fn::ui_human "cog: claude job still running — poll again (re-run finalize)"
    return "$(cog::fn::longrun::signal_code running)"
  fi

  local access effort model account profile command output events stderr
  access="$(jq -r '.engine_meta.access // "read-only"' "$state")"
  effort="$(jq -r '.engine_meta.effort // ""' "$state")"
  model="$(jq -r '.engine_meta.model // ""' "$state")"
  account="$(jq -r '.engine_meta.account // ""' "$state")"
  profile="$(jq -r '.engine_meta.profile // ""' "$state")"
  command="$(jq -r '.engine_meta.command // ""' "$state")"
  output="$(jq -r '.artifacts.output // ""' "$state")"
  events="$(jq -r '.artifacts.stdout // ""' "$state")"
  stderr="$(jq -r '.artifacts.stderr // ""' "$state")"

  # Materialize the output artifact before classifying it. claude carries its
  # final message inside the stream rather than writing a named file, so the
  # runner produces the artifact the caller was promised. Emptiness is only a
  # meaningful signal after this has had its chance to run.
  cog::fn::claude_extract_result "$events" "$output" || true

  local status final_state session_id ok
  if [[ -n $exit_code ]]; then
    status="$(cog::fn::claude_classify_status "$exit_code" "$output")"
  else
    # Wrapper lost before recording the exit code: reconstruct from artifacts.
    status="$(cog::fn::claude_reconstruct_status "$events" "$output")"
    case "$status" in
      ok | empty-output) exit_code=0 ;;
      nonzero) exit_code=1 ;;
      *) exit_code=143 ;;
    esac
  fi
  session_id="$(cog::fn::claude_extract_session "$events" || true)"
  ok="$(cog::fn::runner::bool_for_status "$status")"

  if [[ $ok == true ]]; then
    final_state="finalized-ok"
  elif [[ $exit_source == reconstructed ]]; then
    final_state="lost"
  else
    final_state="finalized-failed"
  fi
  cog::fn::longrun::persist_final "$state" "$final_state" "$exit_code" "$exit_source" >/dev/null

  local json
  json="$(jq -n \
    --arg action run-exec --argjson ok "$ok" --argjson exit_code "$exit_code" \
    --arg status "$status" --arg access "$access" --arg effort "$effort" --arg model "$model" \
    --arg account "$account" --arg profile "$profile" \
    --arg output_file "$output" --arg events_file "$events" --arg stderr_file "$stderr" \
    --arg session_id "$session_id" --arg command "$command" \
    '{action: $action, ok: $ok, exit_code: $exit_code, status: $status, access: $access,
      effort: $effort, model: $model, account: $account, profile: $profile,
      output_file: $output_file, events_file: $events_file, stderr_file: $stderr_file,
      session_id: $session_id, command: $command}')"
  cog::fn::json_emit "$__cog_claude_runner_self_check and .exit_code != null and .status != null and .effort != null and .access != null" "$json"

  # GR4: the exit code is the signal. 0 = ok, 1 = failed; the body carries the
  # status/session_id details the caller reads only when it wants them.
  if [[ $ok == true ]]; then
    return "$(cog::fn::longrun::signal_code ok)"
  fi
  cog::fn::ui_human "cog: claude job ${final_state} (status: ${status}, exit_code: ${exit_code})"
  return "$(cog::fn::longrun::signal_code failed)"
}

# The same preconditions run-exec enforces, exposed so a skill can gate before
# it builds a prompt it would then throw away.
__cog_claude_runner_gate() {
  local out=""
  [[ $# -eq 1 ]] || cog::fn::error_raise "MissingArgument" \
    "invalid gate arguments" "usage: cog claude-runner gate <out.json>" "" ""
  out="$1"
  __cog_claude_runner_preflight "$out"
  cog::fn::ui_data "RESOLVED ${out}"
}

cog::cmd::claude_runner() {
  local mode="${1:-}"
  case "$mode" in
    -h | --help)
      __cog_claude_runner_usage
      ;;
    run-exec)
      shift
      __cog_claude_runner_run_exec "$@"
      ;;
    finalize)
      shift
      __cog_claude_runner_finalize "$@"
      ;;
    gate)
      shift
      __cog_claude_runner_gate "$@"
      ;;
    *)
      cog::fn::error_raise "InvalidInput" \
        "unknown claude-runner mode" "mode: ${mode}" "" "run 'cog claude-runner --help'"
      ;;
  esac
}
