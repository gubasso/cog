# shellcheck shell=bash
: 'desc: Run codex-session orchestration helpers.'

__cog_codex_runner_self_check='.action != null and .ok != null'

__cog_codex_runner_usage() {
  cog::fn::ui_data "Usage: cog codex-runner run-exec --mode <native|fallback|danger|quick-auto> --profile <p> --prompt <file> --output <file> --events <file> [--stderr <file>] [--thread first|last] [--print-command]"
  cog::fn::ui_data "Usage: cog codex-runner run-resume --account <name> --thread-id <id> --profile <p> --prompt <file> --output <file> --events <file> [--stderr <file>] [--print-command]"
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

__cog_codex_runner_run_exec() {
  local mode="" profile="" prompt="" output="" events="" stderr="" thread_selection="" print_command=false
  local command exit_code=0 output_status status thread_id="" account="" reset_eta ok json
  while (($# > 0)); do
    case "$1" in
      --mode)
        mode="${2:-}"
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
      --thread)
        thread_selection="${2:-}"
        shift 2
        ;;
      --print-command)
        print_command=true
        shift
        ;;
      *) cog::fn::error_raise "InvalidInput" "invalid run-exec argument" "argument: $1" "" "run 'cog codex-runner --help'" ;;
    esac
  done
  [[ -n $mode && -n $profile && -n $prompt && -n $output && -n $events ]] || cog::fn::error_raise "MissingArgument" \
    "missing run-exec argument" "usage: cog codex-runner run-exec --mode <mode> --profile <p> --prompt <file> --output <file> --events <file>" "" \
    "run 'cog codex-runner --help'"
  if [[ $mode != danger && $mode != quick-auto && -z $stderr ]]; then
    cog::fn::error_raise "MissingArgument" "missing stderr file" "option: --stderr" "" "native and fallback modes require stderr capture"
  fi

  command="$(cog::fn::codex_exec_command "$mode" "$profile" "$prompt" "$output" "$events" "$stderr")"
  if [[ $print_command == true ]]; then
    cog::fn::ui_data "$command"
    return 0
  fi

  set +e
  cog::fn::codex_exec_run "$mode" "$profile" "$prompt" "$output" "$events" "$stderr"
  exit_code=$?
  set -e
  output_status="$(cog::fn::codex_check_output "$output" "$stderr")"
  status="$(cog::fn::codex_classify_error "$exit_code" "$stderr")"
  [[ $status == ok && $output_status != ok ]] && status="$output_status"
  if [[ -n $thread_selection ]]; then
    thread_id="$(cog::fn::codex_extract_thread "$events" "$thread_selection" || true)"
    [[ -n $thread_id ]] && account="$(cog::fn::codex_lookup_thread_account "$thread_id" || true)"
  fi
  reset_eta="$(cog::fn::codex_extract_reset_eta "$stderr" || true)"
  ok="$(__cog_codex_runner_bool_for_status "$status")"
  json="$(jq -n \
    --arg action run-exec \
    --argjson ok "$ok" \
    --argjson exit_code "$exit_code" \
    --arg status "$status" \
    --arg mode "$mode" \
    --arg profile "$profile" \
    --arg output_file "$output" \
    --arg events_file "$events" \
    --arg stderr_file "$stderr" \
    --arg thread_id "$thread_id" \
    --arg account "$account" \
    --arg reset_eta "$reset_eta" \
    --arg command "$command" \
    '{action: $action, ok: $ok, exit_code: $exit_code, status: $status, mode: $mode,
      profile: $profile, output_file: $output_file, events_file: $events_file,
      stderr_file: $stderr_file, thread_id: $thread_id, account: $account,
      reset_eta: $reset_eta, command: $command}')"
  cog::fn::json_emit "$__cog_codex_runner_self_check and .exit_code != null and .status != null" "$json"
}

__cog_codex_runner_run_resume() {
  local account="" thread_id="" profile="" prompt="" output="" events="" stderr="" print_command=false
  local command exit_code=0 output_status status warning_signal resume_signal reset_eta ok json
  while (($# > 0)); do
    case "$1" in
      --account)
        account="${2:-}"
        shift 2
        ;;
      --thread-id)
        thread_id="${2:-}"
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
      --print-command)
        print_command=true
        shift
        ;;
      *) cog::fn::error_raise "InvalidInput" "invalid run-resume argument" "argument: $1" "" "run 'cog codex-runner --help'" ;;
    esac
  done
  [[ -n $account && -n $thread_id && -n $profile && -n $prompt && -n $output && -n $events ]] || cog::fn::error_raise "MissingArgument" \
    "missing run-resume argument" "usage: cog codex-runner run-resume --account <name> --thread-id <id> --profile <p> --prompt <file> --output <file> --events <file>" "" \
    "run 'cog codex-runner --help'"
  command="$(cog::fn::codex_resume_command "$account" "$profile" "$thread_id" "$prompt" "$output" "$events")"
  if [[ $print_command == true ]]; then
    cog::fn::ui_data "$command"
    return 0
  fi
  set +e
  cog::fn::codex_resume_run "$account" "$profile" "$thread_id" "$prompt" "$output" "$events" "$stderr"
  exit_code=$?
  set -e
  output_status="$(cog::fn::codex_check_output "$output" "$stderr")"
  status="$(cog::fn::codex_classify_error "$exit_code" "$stderr")"
  [[ $status == ok && $output_status != ok ]] && status="$output_status"
  warning_signal="$(cog::fn::codex_resume_warning "$stderr" || true)"
  if [[ -n $warning_signal ]]; then
    resume_signal="$warning_signal"
  else
    resume_signal="$status"
  fi
  reset_eta="$(cog::fn::codex_extract_reset_eta "$stderr" || true)"
  ok="$(__cog_codex_runner_bool_for_status "$status")"
  json="$(jq -n \
    --arg action run-resume \
    --argjson ok "$ok" \
    --argjson exit_code "$exit_code" \
    --arg status "$status" \
    --arg resume_signal "$resume_signal" \
    --arg account "$account" \
    --arg thread_id "$thread_id" \
    --arg output_file "$output" \
    --arg events_file "$events" \
    --arg stderr_file "$stderr" \
    --arg reset_eta "$reset_eta" \
    --arg command "$command" \
    '{action: $action, ok: $ok, exit_code: $exit_code, status: $status,
      resume_signal: $resume_signal, account: $account, thread_id: $thread_id,
      output_file: $output_file, events_file: $events_file, stderr_file: $stderr_file,
      reset_eta: $reset_eta, command: $command}')"
  cog::fn::json_emit "$__cog_codex_runner_self_check and .resume_signal != null" "$json"
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
