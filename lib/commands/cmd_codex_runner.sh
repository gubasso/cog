# shellcheck shell=bash
: 'desc: Run codex-session orchestration helpers.'

__cog_codex_runner_self_check='.action != null and .ok != null'

__cog_codex_runner_usage() {
  cog::fn::ui_data "Usage: cog codex-runner run-exec --mode <native|fallback|danger|quick-auto> [--access <read-only|write>] --effort <tier> --prompt <file> --output <file> --events <file> --state <file> [--stderr <file>] [--cwd <dir>] [--thread first|last] [--print-command]"
  cog::fn::ui_data "Usage: cog codex-runner run-resume --account <name> --thread-id <id> [--access <read-only|write>] --effort <tier> --prompt <file> --output <file> --events <file> --state <file> [--stderr <file>] [--cwd <dir>] [--print-command]"
  cog::fn::ui_data "Usage: cog codex-runner status --state <file>"
  cog::fn::ui_data "Usage: cog codex-runner finalize --state <file> [--max-wall <secs>] [--poll <secs>]"
  cog::fn::ui_data "Usage: cog codex-runner cancel --state <file> [--signal TERM|KILL]"
  cog::fn::ui_data "Usage: cog codex-runner extract-thread <events.jsonl> <first|last>"
  cog::fn::ui_data "Usage: cog codex-runner check-output <out> <stderr>"
  cog::fn::ui_data "Usage: cog codex-runner classify-error <exit-code> <stderr>"
  cog::fn::ui_data "Usage: cog codex-runner snapshot-pre <run-dir> <out.snap>"
  cog::fn::ui_data "Usage: cog codex-runner snapshot-post <run-dir> <pre.snap> <post.snap> <diff>"
  cog::fn::ui_data "Usage: cog codex-runner gate [codex|sandbox] <out.json>"
  cog::fn::ui_data "Usage: cog codex-runner verify-proof --proof <diff> --artifact <file> [--artifact <file>...] [--require-json <jq-expr>]"
  cog::fn::ui_data "Usage: cog codex-runner orientation <read-only|write>"
  cog::fn::ui_data "Usage: cog codex-runner explain-status <status>"
}

__cog_codex_runner_bool_for_status() {
  [[ $1 == ok ]] && printf '%s\n' true || printf '%s\n' false
}

# Derive the durable-job label from the --state filename (strip .longrun.json).
__cog_codex_runner_label_for_state() {
  local state_file="$1" base
  base="$(basename -- "$state_file")"
  base="${base%.longrun.json}"
  base="${base%.json}"
  printf '%s\n' "$base"
}

# Fail closed on a relative artifact path. A durable codex job launches from the
# project repo (see __cog_codex_runner_resolve_cwd), so a relative --state /
# --output / --events / --stderr resolves against the project tree and scatters
# artifacts loose in it. Require an absolute path from a run dir instead.
__cog_codex_runner_require_abs() {
  local option="$1" value="$2"
  # shellcheck disable=SC2016 # literal $RUN_DIR in the operator-facing hint, not an expansion
  [[ $value == /* ]] || cog::fn::error_raise "InvalidInput" \
    "codex-runner artifact path must be absolute" "option: ${option}, path: ${value}" \
    "relative paths resolve against the job cwd (the project repo) and scatter artifacts into it" \
    'allocate RUN_DIR="$(cog rundir <prefix>)" and pass $RUN_DIR/<file>'
}

# Extract every artifact-write target a prompt references via a --output flag.
# A prompt may embed an instruction like `$plan-oneshot --output <RUN_DIR>/prepared-plan.md`
# (the inner agent then runs `cog plan-doc save --output <RUN_DIR>/prepared-plan.md`); the
# collision key is always the --output value, so one regex covers both spellings.
# Backslash-continued lines are folded first so a flag split across lines still resolves.
# Angle-bracket <placeholder> tokens are dropped; nothing is eval'd, so a literal $VAR
# stays literal — no expansion, no injection, no false positive from a `$VAR` mention.
__cog_codex_runner_extract_prompt_targets() {
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

# Fail closed before launch when the runner's own --output (Codex's closing
# --output-last-message) equals an artifact the prompt tells the inner agent to
# write. Codex overwrites --output-last-message with its final message; if that
# path is also where an embedded plan/artifact write lands, the closing message
# clobbers the durable artifact. Compare on exact absolute-path equality
# (realpath -m normalizes .././dup-slashes without requiring existence) so an
# unrelated --output mentioned in the brief never trips it. An unreadable prompt
# defers to the downstream prompt-readable check in fn_codex.sh.
__cog_codex_runner_guard_output_collision() {
  local output="$1" prompt="$2" target output_abs target_abs
  [[ -r $prompt ]] || return 0
  output_abs="$(realpath -m -- "$output")"
  while IFS= read -r target; do
    [[ -n $target ]] || continue
    target_abs="$(realpath -m -- "$target")"
    [[ $output_abs == "$target_abs" ]] || continue
    # shellcheck disable=SC2016 # literal $RUN_DIR in the operator-facing hint, not an expansion
    cog::fn::error_raise "InvalidInput" \
      "codex-runner --output collides with a prompt artifact-write target" \
      "path: ${output}" \
      "the runner --output captures Codex's closing message and would clobber the artifact the prompt writes there" \
      'route the last-message capture to a distinct $RUN_DIR/<label>-codex-output.md'
  done < <(__cog_codex_runner_extract_prompt_targets "$prompt")
}

# Resolve the durable-job working directory. Codex `exec` refuses with "not
# inside a trusted directory" when its cwd is neither a git worktree nor a
# configured trusted project, so the job must launch from the project repo
# rather than the scratch RUN_DIR the observer may be sitting in. An explicit
# --cwd wins; otherwise resolve the git repo root of $PWD; otherwise keep $PWD.
__cog_codex_runner_resolve_cwd() {
  local cwd="${1:-}"
  if [[ -z $cwd ]]; then
    cwd="$(cog::fn::git_root_for "$PWD" 2>/dev/null || true)"
    [[ -n $cwd ]] || cwd="$PWD"
  fi
  printf '%s\n' "$cwd"
}

# run-exec is now a non-blocking LAUNCHER. Codex runs as a cog-owned durable job
# (detached in its own session) so a Bash-tool 600s SIGTERM cannot kill it.
# The result JSON is produced later by `finalize`, reconstructed from durable
# artifacts; this call only starts the job and prints STATE_FILE=/JOB_PGID=.
__cog_codex_runner_run_exec() {
  local mode="" access="read-only" effort="" prompt="" output="" events="" stderr="" state="" thread_selection="" cwd="" print_command=false
  local command label run_dir engine_meta pgid
  local -a argv=()
  while (($# > 0)); do
    case "$1" in
      --mode)
        mode="${2:-}"
        shift 2
        ;;
      --effort)
        effort="${2:-}"
        shift 2
        ;;
      --access)
        access="${2:-}"
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
      --thread)
        thread_selection="${2:-}"
        shift 2
        ;;
      --cwd)
        cwd="${2:-}"
        shift 2
        ;;
      --print-command)
        print_command=true
        shift
        ;;
      *) cog::fn::error_raise "InvalidInput" "invalid run-exec argument" "argument: $1" "" "run 'cog codex-runner --help'" ;;
    esac
  done
  [[ -n $mode && -n $effort && -n $prompt && -n $output && -n $events ]] || cog::fn::error_raise "MissingArgument" \
    "missing run-exec argument" "usage: cog codex-runner run-exec --mode <mode> [--access <read-only|write>] --effort <tier> --prompt <file> --output <file> --events <file> --state <file>" "" \
    "run 'cog codex-runner --help'"
  case "$access" in
    read-only | write) ;;
    *) cog::fn::error_raise "InvalidInput" "invalid run-exec access" "access: ${access}" "expected read-only or write" "" ;;
  esac
  if [[ $access == write ]] && ! cog::fn::codex_mode_is_write_capable "$mode"; then
    cog::fn::error_raise "InvalidInput" \
      "write access requires a write-capable mode" "mode: ${mode}, access: ${access}" \
      "only danger is write-capable" "use --mode danger or --access read-only"
  fi

  command="$(cog::fn::codex_exec_command "$mode" "$effort" "$prompt" "$output" "$events" "$stderr")"
  if [[ $print_command == true ]]; then
    cog::fn::ui_data "$command"
    return 0
  fi

  [[ -n $state ]] || cog::fn::error_raise "MissingArgument" \
    "missing --state" "option: --state" "every codex run is a durable job" "pass --state <run-dir>/<label>.longrun.json"
  label="$(__cog_codex_runner_label_for_state "$state")"
  run_dir="$(dirname -- "$state")"
  [[ -n $stderr ]] || stderr="${run_dir}/${label}.stderr.log"

  cwd="$(__cog_codex_runner_resolve_cwd "$cwd")"

  __cog_codex_runner_require_abs --state "$state"
  __cog_codex_runner_require_abs --output "$output"
  __cog_codex_runner_require_abs --events "$events"
  __cog_codex_runner_require_abs --stderr "$stderr"

  __cog_codex_runner_guard_output_collision "$output" "$prompt"

  cog::fn::codex_exec_argv "$mode" "$effort" "$prompt" "$output" argv
  engine_meta="$(jq -cn \
    --arg engine_action run-exec --arg mode "$mode" --arg access "$access" \
    --arg effort "$effort" --arg thread_selection "$thread_selection" --arg command "$command" \
    '{engine_action: $engine_action, mode: $mode, access: $access, effort: $effort,
      thread_selection: $thread_selection, command: $command}')"

  cog::fn::longrun::start --state "$state" --label "$label" --cwd "$cwd" \
    --stdout "$events" --stderr "$stderr" --output "$output" \
    --engine codex --engine-meta "$engine_meta" -- "${argv[@]}"
  pgid="$(jq -r '.pgid' "$state" 2>/dev/null || true)"
  cog::fn::ui_data "STATE_FILE=${state}"
  cog::fn::ui_data "JOB_PGID=${pgid}"
}

__cog_codex_runner_run_resume() {
  local account="" thread_id="" effort="" prompt="" output="" events="" stderr="" state="" cwd="" print_command=false
  local access="read-only"
  local command label run_dir engine_meta pgid
  local -a argv=()
  while (($# > 0)); do
    case "$1" in
      --access)
        access="${2:-}"
        shift 2
        ;;
      --account)
        account="${2:-}"
        shift 2
        ;;
      --thread-id)
        thread_id="${2:-}"
        shift 2
        ;;
      --effort)
        effort="${2:-}"
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
      --cwd)
        cwd="${2:-}"
        shift 2
        ;;
      --print-command)
        print_command=true
        shift
        ;;
      *) cog::fn::error_raise "InvalidInput" "invalid run-resume argument" "argument: $1" "" "run 'cog codex-runner --help'" ;;
    esac
  done
  [[ -n $account && -n $thread_id && -n $effort && -n $prompt && -n $output && -n $events ]] || cog::fn::error_raise "MissingArgument" \
    "missing run-resume argument" "usage: cog codex-runner run-resume --account <name> --thread-id <id> [--access <read-only|write>] --effort <tier> --prompt <file> --output <file> --events <file> --state <file>" "" \
    "run 'cog codex-runner --help'"
  # A resume inherits nothing from the cold round's sandbox, so access is
  # declared per call and defaults closed: a warm round of a read-only review
  # stays read-only unless the caller asks for write.
  case "$access" in
    read-only | write) ;;
    *) cog::fn::error_raise "InvalidInput" "invalid run-resume access" "access: ${access}" "expected read-only or write" "" ;;
  esac
  command="$(cog::fn::codex_resume_command "$account" "$effort" "$thread_id" "$prompt" "$output" "$events" "$access")"
  if [[ $print_command == true ]]; then
    cog::fn::ui_data "$command"
    return 0
  fi

  [[ -n $state ]] || cog::fn::error_raise "MissingArgument" \
    "missing --state" "option: --state" "every codex run is a durable job" "pass --state <run-dir>/<label>.longrun.json"
  label="$(__cog_codex_runner_label_for_state "$state")"
  run_dir="$(dirname -- "$state")"
  [[ -n $stderr ]] || stderr="${run_dir}/${label}.stderr.log"

  cwd="$(__cog_codex_runner_resolve_cwd "$cwd")"

  __cog_codex_runner_require_abs --state "$state"
  __cog_codex_runner_require_abs --output "$output"
  __cog_codex_runner_require_abs --events "$events"
  __cog_codex_runner_require_abs --stderr "$stderr"

  __cog_codex_runner_guard_output_collision "$output" "$prompt"

  cog::fn::codex_resume_argv "$account" "$effort" "$thread_id" "$prompt" "$output" argv "$access"
  engine_meta="$(jq -cn \
    --arg engine_action run-resume --arg account "$account" --arg thread_id "$thread_id" \
    --arg effort "$effort" --arg access "$access" --arg command "$command" \
    '{engine_action: $engine_action, account: $account, thread_id: $thread_id,
      effort: $effort, access: $access, command: $command}')"

  cog::fn::longrun::start --state "$state" --label "$label" --cwd "$cwd" \
    --stdout "$events" --stderr "$stderr" --output "$output" \
    --engine codex --engine-meta "$engine_meta" -- "${argv[@]}"
  pgid="$(jq -r '.pgid' "$state" 2>/dev/null || true)"
  cog::fn::ui_data "STATE_FILE=${state}"
  cog::fn::ui_data "JOB_PGID=${pgid}"
}

__cog_codex_runner_require_state() {
  local state="$1"
  [[ -n $state ]] || cog::fn::error_raise "MissingArgument" \
    "missing --state" "option: --state" "" "run 'cog codex-runner --help'"
  [[ -r $state ]] || cog::fn::error_raise "InputNotFound" \
    "codex job state not found" "path: ${state}" "" "check the --state path"
}

__cog_codex_runner_status() {
  local state=""
  while (($# > 0)); do
    case "$1" in
      --state)
        state="${2:-}"
        shift 2
        ;;
      *) cog::fn::error_raise "InvalidInput" "invalid status argument" "argument: $1" "" "run 'cog codex-runner --help'" ;;
    esac
  done
  __cog_codex_runner_require_state "$state"
  cog::fn::json_emit '(.state | type == "string")' "$(cog::fn::longrun::status_json "$state")"
}

__cog_codex_runner_cancel() {
  local state="" signal=TERM
  while (($# > 0)); do
    case "$1" in
      --state)
        state="${2:-}"
        shift 2
        ;;
      --signal)
        signal="${2:-}"
        shift 2
        ;;
      *) cog::fn::error_raise "InvalidInput" "invalid cancel argument" "argument: $1" "" "run 'cog codex-runner --help'" ;;
    esac
  done
  __cog_codex_runner_require_state "$state"
  case "$signal" in
    TERM | KILL) ;;
    *) cog::fn::error_raise "InvalidInput" "invalid signal" "signal: ${signal}" "expected TERM or KILL" "" ;;
  esac
  cog::fn::json_emit '(.state | type == "string")' "$(cog::fn::longrun::cancel "$state" "$signal")"
}

# Classify a finished (or lost) codex job from durable artifacts and emit the
# run-exec / run-resume result JSON shape callers already consume. Safe to call
# even if the launching observer was killed: nothing here depends on it.
__cog_codex_runner_finalize() {
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
      --poll)
        poll="${2:-}"
        shift 2
        ;;
      *) cog::fn::error_raise "InvalidInput" "invalid finalize argument" "argument: $1" "" "run 'cog codex-runner --help'" ;;
    esac
  done
  __cog_codex_runner_require_state "$state"
  [[ $max_wall =~ ^[0-9]+$ ]] || max_wall=0

  ((max_wall > 0)) && cog::fn::longrun::wait "$state" "$max_wall" "$poll" >/dev/null

  local resolve base exit_code exit_source
  resolve="$(cog::fn::longrun::resolve_exit "$state")"
  base="$(jq -r '.state' <<<"$resolve")"
  exit_code="$(jq -r '.exit_code // ""' <<<"$resolve")"
  exit_source="$(jq -r '.exit_source // ""' <<<"$resolve")"

  if [[ $base == running ]]; then
    # Not terminal yet. Never classify a live job (its events file is mid-write).
    # GR4: signal "still running" via exit 75; the caller simply re-runs finalize.
    cog::fn::json_emit '(.state | type == "string")' "$(jq -c '. + {ok: false}' "$state")"
    cog::fn::ui_human "cog: codex job still running — poll again (re-run finalize)"
    return "$(cog::fn::longrun::signal_code running)"
  fi

  local engine_action mode access effort thread_selection account thread_id command output events stderr
  engine_action="$(jq -r '.engine_meta.engine_action // "run-exec"' "$state")"
  mode="$(jq -r '.engine_meta.mode // ""' "$state")"
  access="$(jq -r '.engine_meta.access // "read-only"' "$state")"
  effort="$(jq -r '.engine_meta.effort // ""' "$state")"
  thread_selection="$(jq -r '.engine_meta.thread_selection // ""' "$state")"
  account="$(jq -r '.engine_meta.account // ""' "$state")"
  thread_id="$(jq -r '.engine_meta.thread_id // ""' "$state")"
  command="$(jq -r '.engine_meta.command // ""' "$state")"
  output="$(jq -r '.artifacts.output // ""' "$state")"
  events="$(jq -r '.artifacts.stdout // ""' "$state")"
  stderr="$(jq -r '.artifacts.stderr // ""' "$state")"

  local status output_status final_state reset_eta ok
  if [[ -n $exit_code ]]; then
    output_status="$(cog::fn::codex_check_output "$output" "$stderr")"
    status="$(cog::fn::codex_classify_error "$exit_code" "$stderr")"
    [[ $status == ok && $output_status != ok ]] && status="$output_status"
  else
    # Wrapper lost before recording the exit code: reconstruct from artifacts.
    status="$(cog::fn::codex_reconstruct_status "$events" "$output")"
    case "$status" in
      ok | empty-output) exit_code=0 ;;
      nonzero) exit_code=1 ;;
      *) exit_code=143 ;;
    esac
  fi
  reset_eta="$(cog::fn::codex_extract_reset_eta "$stderr" || true)"
  ok="$(__cog_codex_runner_bool_for_status "$status")"

  if [[ $ok == true ]]; then
    final_state="finalized-ok"
  elif [[ $exit_source == reconstructed ]]; then
    final_state="lost"
  else
    final_state="finalized-failed"
  fi
  cog::fn::longrun::persist_final "$state" "$final_state" "$exit_code" "$exit_source" >/dev/null

  local json
  if [[ $engine_action == run-resume ]]; then
    local warning_signal resume_signal
    warning_signal="$(cog::fn::codex_resume_warning "$stderr" || true)"
    if [[ -n $warning_signal ]]; then resume_signal="$warning_signal"; else resume_signal="$status"; fi
    json="$(jq -n \
      --arg action run-resume --argjson ok "$ok" --argjson exit_code "$exit_code" \
      --arg status "$status" --arg resume_signal "$resume_signal" --arg effort "$effort" \
      --arg access "$access" --arg account "$account" --arg thread_id "$thread_id" \
      --arg output_file "$output" --arg events_file "$events" --arg stderr_file "$stderr" \
      --arg reset_eta "$reset_eta" --arg command "$command" \
      '{action: $action, ok: $ok, exit_code: $exit_code, status: $status,
        resume_signal: $resume_signal, effort: $effort, access: $access, account: $account, thread_id: $thread_id,
        output_file: $output_file, events_file: $events_file, stderr_file: $stderr_file,
        reset_eta: $reset_eta, command: $command}')"
    cog::fn::json_emit "$__cog_codex_runner_self_check and .resume_signal != null and .effort != null" "$json"
  else
    local extracted_thread="" extracted_account=""
    if [[ -n $thread_selection ]]; then
      extracted_thread="$(cog::fn::codex_extract_thread "$events" "$thread_selection" || true)"
      [[ -n $extracted_thread ]] && extracted_account="$(cog::fn::codex_lookup_thread_account "$extracted_thread" || true)"
    fi
    json="$(jq -n \
      --arg action run-exec --argjson ok "$ok" --argjson exit_code "$exit_code" \
      --arg status "$status" --arg mode "$mode" --arg access "$access" --arg effort "$effort" \
      --arg output_file "$output" --arg events_file "$events" --arg stderr_file "$stderr" \
      --arg thread_id "$extracted_thread" --arg account "$extracted_account" \
      --arg reset_eta "$reset_eta" --arg command "$command" \
      '{action: $action, ok: $ok, exit_code: $exit_code, status: $status, mode: $mode,
        access: $access, effort: $effort, output_file: $output_file, events_file: $events_file,
        stderr_file: $stderr_file, thread_id: $thread_id, account: $account,
        reset_eta: $reset_eta, command: $command}')"
    cog::fn::json_emit "$__cog_codex_runner_self_check and .exit_code != null and .status != null and .effort != null and .access != null" "$json"
  fi

  # GR4: the exit code is the signal. 0 = ok, 1 = failed; the body carries the
  # status/thread_id/account details the caller reads only when it wants them.
  if [[ $ok == true ]]; then
    return "$(cog::fn::longrun::signal_code ok)"
  fi
  cog::fn::ui_human "cog: codex job ${final_state} (status: ${status}, exit_code: ${exit_code})"
  return "$(cog::fn::longrun::signal_code failed)"
}

__cog_codex_runner_extract_thread() {
  [[ $# -eq 2 ]] || cog::fn::error_raise "MissingArgument" \
    "invalid extract-thread arguments" "usage: cog codex-runner extract-thread <events.jsonl> <first|last>" "" ""
  local thread_id ok json
  thread_id="$(cog::fn::codex_extract_thread "$1" "$2" || true)"
  [[ -n $thread_id ]] && ok=true || ok=false
  json="$(jq -n --arg action extract-thread --argjson ok "$ok" --arg events_file "$1" --arg selection "$2" --arg thread_id "$thread_id" \
    '{action: $action, ok: $ok, events_file: $events_file, selection: $selection, thread_id: $thread_id}')"
  cog::fn::json_emit "$__cog_codex_runner_self_check and .selection != null" "$json"
}

__cog_codex_runner_check_output() {
  [[ $# -eq 2 ]] || cog::fn::error_raise "MissingArgument" \
    "invalid check-output arguments" "usage: cog codex-runner check-output <out> <stderr>" "" ""
  local status ok signal="" json
  status="$(cog::fn::codex_check_output "$1" "$2")"
  ok="$(__cog_codex_runner_bool_for_status "$status")"
  [[ $status == sigterm ]] && signal=SIGTERM
  json="$(jq -n --arg action check-output --argjson ok "$ok" --arg status "$status" --arg output_file "$1" --arg stderr_file "$2" --arg signal "$signal" \
    '{action: $action, ok: $ok, status: $status, output_file: $output_file, stderr_file: $stderr_file, signal: $signal}')"
  cog::fn::json_emit "$__cog_codex_runner_self_check and .status != null" "$json"
}

__cog_codex_runner_classify_error() {
  [[ $# -eq 2 ]] || cog::fn::error_raise "MissingArgument" \
    "invalid classify-error arguments" "usage: cog codex-runner classify-error <exit-code> <stderr>" "" ""
  local status ok signal="" reset_eta json
  status="$(cog::fn::codex_classify_error "$1" "$2")"
  ok="$(__cog_codex_runner_bool_for_status "$status")"
  [[ $status == sigterm ]] && signal=SIGTERM
  reset_eta="$(cog::fn::codex_extract_reset_eta "$2" || true)"
  json="$(jq -n --arg action classify-error --argjson ok "$ok" --argjson exit_code "$1" --arg status "$status" --arg signal "$signal" --arg reset_eta "$reset_eta" \
    '{action: $action, ok: $ok, exit_code: $exit_code, status: $status, signal: $signal, reset_eta: $reset_eta}')"
  cog::fn::json_emit "$__cog_codex_runner_self_check and .exit_code != null and .status != null" "$json"
}

__cog_codex_runner_snapshot_pre() {
  [[ $# -eq 2 ]] || cog::fn::error_raise "MissingArgument" \
    "invalid snapshot-pre arguments" "usage: cog codex-runner snapshot-pre <run-dir> <out.snap>" "" ""
  local json
  cog::fn::rundir_snapshot "$1" "$2"
  json="$(jq -n --arg action snapshot-pre --argjson ok true --arg run_dir "$1" --arg snapshot "$2" \
    '{action: $action, ok: $ok, run_dir: $run_dir, snapshot: $snapshot}')"
  cog::fn::json_emit "$__cog_codex_runner_self_check and .snapshot != null" "$json"
}

__cog_codex_runner_snapshot_post() {
  [[ $# -eq 4 ]] || cog::fn::error_raise "MissingArgument" \
    "invalid snapshot-post arguments" "usage: cog codex-runner snapshot-post <run-dir> <pre.snap> <post.snap> <diff>" "" ""
  local json
  cog::fn::rundir_snapshot "$1" "$3"
  cog::fn::rundir_snapshot_diff "$2" "$3" "$4"
  json="$(jq -n --arg action snapshot-post --argjson ok true --arg run_dir "$1" --arg pre "$2" --arg post "$3" --arg diff "$4" \
    '{action: $action, ok: $ok, run_dir: $run_dir, pre_snapshot: $pre, post_snapshot: $post, diff: $diff}')"
  cog::fn::json_emit "$__cog_codex_runner_self_check and .diff != null" "$json"
}

__cog_codex_runner_gate() {
  local check=codex out="" available health
  if [[ $# -eq 2 ]]; then
    check="$1"
    out="$2"
  elif [[ $# -eq 1 ]]; then
    out="$1"
  else
    cog::fn::error_raise "MissingArgument" "invalid gate arguments" "usage: cog codex-runner gate [codex|sandbox] <out.json>" "" ""
  fi
  case "$check" in
    codex | sandbox) ;;
    *) cog::fn::error_raise "InvalidInput" "invalid gate check" "check: ${check}" "expected codex or sandbox" "" ;;
  esac
  if ! declare -F __cog_preflight_codex >/dev/null; then
    # shellcheck source=/dev/null
    source "${LIB_DIR}/commands/cmd_preflight.sh"
  fi
  case "$check" in
    codex) __cog_preflight_codex "$out" ;;
    sandbox) __cog_preflight_sandbox "$out" ;;
  esac
  jq -e '.codex_session.available != null' "$out" >/dev/null 2>&1 || cog::fn::error_raise "InvalidJsonOutput" \
    "preflight produced no codex_session fragment" "path: ${out}" "" "report this cog bug"
  available="$(jq -r '.codex_session.available' "$out")"
  [[ $available == true ]] || cog::fn::error_raise "InvalidInput" \
    "codex-session is not available on PATH" "path: ${out}" "" "install codex-session or add it to PATH"
  health="$(jq -r '.codex_session.health' "$out")"
  [[ $health == ok ]] || cog::fn::error_raise "InvalidInput" \
    "no healthy codex-session accounts" "health: ${health}" "" "check codex-session account status"
}

__cog_codex_runner_json_array() {
  if (($# == 0)); then
    jq -cn '[]'
  else
    printf '%s\n' "$@" | jq -R . | jq -s .
  fi
}

__cog_codex_runner_verify_proof_json() {
  local proof="" require_json="" ok=true reason="" last=""
  local -a artifacts=() reasons=()
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
      *) cog::fn::error_raise "InvalidInput" "invalid verify-proof argument" "argument: $1" "" "run 'cog codex-runner --help'" ;;
    esac
  done
  [[ -n $proof && ${#artifacts[@]} -ge 1 ]] || cog::fn::error_raise "MissingArgument" \
    "missing verify-proof argument" "usage: cog codex-runner verify-proof --proof <diff> --artifact <file>" "" ""
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
    --argjson artifacts "$(__cog_codex_runner_json_array "${artifacts[@]}")" \
    --arg proof "$proof" \
    '{action: $action, ok: $ok, reason: (if $reason == "" then null else $reason end),
      artifacts: $artifacts, proof: $proof}'
}

__cog_codex_runner_verify_proof() {
  local json
  json="$(__cog_codex_runner_verify_proof_json "$@")"
  cog::fn::json_emit "$__cog_codex_runner_self_check and (.artifacts | type == \"array\")" "$json"
  jq -e '.ok == true' <<<"$json" >/dev/null || cog::fn::error_raise "InvalidInput" \
    "delegation proof is incomplete" "" "$(jq -r '.reason' <<<"$json")" "check artifacts and proof diff"
}

cog::cmd::codex_runner() {
  local mode="${1:-}"
  case "$mode" in
    -h | --help)
      __cog_codex_runner_usage
      ;;
    run-exec)
      shift
      __cog_codex_runner_run_exec "$@"
      ;;
    run-resume)
      shift
      __cog_codex_runner_run_resume "$@"
      ;;
    status)
      shift
      __cog_codex_runner_status "$@"
      ;;
    finalize)
      shift
      __cog_codex_runner_finalize "$@"
      ;;
    cancel)
      shift
      __cog_codex_runner_cancel "$@"
      ;;
    extract-thread)
      shift
      __cog_codex_runner_extract_thread "$@"
      ;;
    check-output)
      shift
      __cog_codex_runner_check_output "$@"
      ;;
    classify-error)
      shift
      __cog_codex_runner_classify_error "$@"
      ;;
    snapshot-pre)
      shift
      __cog_codex_runner_snapshot_pre "$@"
      ;;
    snapshot-post)
      shift
      __cog_codex_runner_snapshot_post "$@"
      ;;
    gate)
      shift
      __cog_codex_runner_gate "$@"
      ;;
    verify-proof)
      shift
      __cog_codex_runner_verify_proof "$@"
      ;;
    orientation)
      shift
      [[ $# -eq 1 ]] || cog::fn::error_raise "MissingArgument" \
        "invalid orientation arguments" \
        "usage: cog codex-runner orientation <read-only|write>" "" \
        "run 'cog codex-runner --help'"
      cog::fn::codex_orientation "$1"
      ;;
    explain-status)
      shift
      [[ $# -eq 1 ]] || cog::fn::error_raise "MissingArgument" \
        "invalid explain-status arguments" \
        "usage: cog codex-runner explain-status <status>" "" \
        "run 'cog codex-runner --help'"
      cog::fn::codex_explain_status "$1"
      ;;
    *)
      cog::fn::error_raise "InvalidInput" \
        "unknown codex-runner mode" "mode: ${mode}" "" "run 'cog codex-runner --help'"
      ;;
  esac
}
