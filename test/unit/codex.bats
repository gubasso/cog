setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export LIB_DIR="${BATS_TEST_DIRNAME}/../../lib"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  export CODEX_FAKE_LOG="${BATS_TEST_TMPDIR}/codex-argv.log"
  export TIMEOUT_FAKE_LOG="${BATS_TEST_TMPDIR}/timeout-argv.log"
  mkdir -p "$HOME" "$XDG_STATE_HOME" "${BATS_TEST_TMPDIR}/fakebin"
  cat >"${BATS_TEST_TMPDIR}/fakebin/codex-session" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${CODEX_FAKE_LOG}"
if [[ $* == "account current --format json" ]]; then
  printf '%s\n' '{"name":"fallback-account"}'
else
  printf '%s\n' '{"type":"thread.started","thread_id":"from-fake"}'
fi
EOF
  cat >"${BATS_TEST_TMPDIR}/fakebin/timeout" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${TIMEOUT_FAKE_LOG}"
shift
"$@"
EOF
  chmod +x "${BATS_TEST_TMPDIR}/fakebin/codex-session" "${BATS_TEST_TMPDIR}/fakebin/timeout"
  export PATH="${BATS_TEST_TMPDIR}/fakebin:${PATH}"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/helpers.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_ui_print.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_log.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_error_raise.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_codex.sh"
}

@test "codex_exec_command renders native fallback quick-auto and danger" {
  run cog::fn::codex_exec_command native medium prompt.md out.md events.jsonl stderr.log
  assert_success
  [[ $output == *"codex-session exec -c model_reasoning_effort=medium --sandbox read-only --json"* ]]
  [[ $output == *'2> "stderr.log"'* ]]

  run cog::fn::codex_exec_command fallback medium prompt.md out.md events.jsonl stderr.log
  assert_success
  [[ $output == *"sandbox_permissions"* ]]

  run cog::fn::codex_exec_command quick-auto medium prompt.md out.md events.jsonl
  assert_success
  [[ $output == *"--account auto exec -c model_reasoning_effort=medium --sandbox read-only --json"* ]]

  run cog::fn::codex_exec_command danger medium prompt.md out.md events.jsonl
  assert_success
  [[ $output == *"--dangerously-bypass-approvals-and-sandbox --json"* ]]
}

@test "codex_exec_command accepts xhigh and forwards unchanged" {
  run cog::fn::codex_exec_command native xhigh prompt.md out.md events.jsonl stderr.log

  assert_success
  [[ $output == *"codex-session exec -c model_reasoning_effort=xhigh --sandbox read-only --json"* ]]
}

@test "codex_exec_command rejects unknown effort with updated allowlist" {
  run --separate-stderr cog::fn::codex_exec_command native unknown prompt.md out.md events.jsonl stderr.log

  assert_failure 64
  [[ $stderr == *"err.kind: InvalidInput"* ]]
  [[ $stderr == *"expected minimal, low, medium, high, or xhigh"* ]]
}

@test "codex_mode_is_write_capable only allows danger" {
  run cog::fn::codex_mode_is_write_capable danger
  assert_success

  run cog::fn::codex_mode_is_write_capable native
  assert_failure

  run cog::fn::codex_mode_is_write_capable fallback
  assert_failure

  run cog::fn::codex_mode_is_write_capable quick-auto
  assert_failure

  run cog::fn::codex_mode_is_write_capable bogus
  assert_failure
  [[ $output == *"mode"* ]]
}

@test "codex_resume_command renders resume command" {
  run cog::fn::codex_resume_command acct medium thread-1 prompt.md out.md events.jsonl

  assert_success
  [[ $output == *'codex-session --account "acct" exec -c model_reasoning_effort=medium resume "thread-1"'* ]]
}

@test "codex_exec_run calls fake codex-session with prompt content" {
  local prompt="${BATS_TEST_TMPDIR}/prompt.md"
  local out="${BATS_TEST_TMPDIR}/out.md"
  local events="${BATS_TEST_TMPDIR}/events.jsonl"
  local err="${BATS_TEST_TMPDIR}/stderr.log"
  printf '%s\n' "hello prompt" >"$prompt"

  run cog::fn::codex_exec_run native medium "$prompt" "$out" "$events" "$err"

  assert_success
  assert_file_contains "$CODEX_FAKE_LOG" "exec -c model_reasoning_effort=medium --sandbox read-only --json --output-last-message $out hello prompt"
  assert_file_contains "$events" "from-fake"
}

@test "codex_exec_run rejects invalid mode and unreadable prompt" {
  run --separate-stderr cog::fn::codex_exec_run nope medium "${BATS_TEST_TMPDIR}/missing" out events err
  assert_failure 64
  [[ $stderr == *"err.kind: InvalidInput"* ]]

  run --separate-stderr cog::fn::codex_exec_run native medium "${BATS_TEST_TMPDIR}/missing" out events err
  assert_failure 66
  [[ $stderr == *"err.kind: InputUnreadable"* ]]
}

@test "codex_sandbox_probe calls timeout and codex-session probe" {
  local probe="${BATS_TEST_TMPDIR}/probe.jsonl"
  local last="${BATS_TEST_TMPDIR}/last.md"

  run cog::fn::codex_sandbox_probe "$probe" "$last" 7

  assert_success
  assert_file_contains "$TIMEOUT_FAKE_LOG" "7 codex-session exec --sandbox read-only --json"
  assert_file_contains "$CODEX_FAKE_LOG" "model=gpt-5.4-mini"
  assert_file_contains "$probe" "from-fake"
}

@test "codex_extract_thread returns first and last thread ids" {
  local events="${BATS_TEST_TMPDIR}/events.jsonl"
  printf '%s\n' \
    '{"type":"thread.started","thread_id":"first"}' \
    '{"type":"other"}' \
    '{"type":"thread.started","thread_id":"last"}' >"$events"

  run cog::fn::codex_extract_thread "$events" first
  assert_success
  assert_output first

  run cog::fn::codex_extract_thread "$events" last
  assert_success
  assert_output last
}

@test "codex_lookup_thread_account prefers index and falls back to current account" {
  local index_dir="${XDG_STATE_HOME}/codex-session"
  mkdir -p "$index_dir"
  printf '%s\n' '{"thread-id":"thread-1","account":"indexed"}' >"$index_dir/thread-index.jsonl"

  run cog::fn::codex_lookup_thread_account thread-1
  assert_success
  assert_output indexed

  run cog::fn::codex_lookup_thread_account missing-thread
  assert_success
  assert_output fallback-account
}

@test "codex_check_output returns empty-output sigterm and ok" {
  local out="${BATS_TEST_TMPDIR}/out.md"
  local err="${BATS_TEST_TMPDIR}/stderr.log"

  run cog::fn::codex_check_output "$out" "$err"
  assert_success
  assert_output empty-output

  printf '%s\n' "message" >"$out"
  printf '%s\n' "terminated due to a signal" >"$err"
  run cog::fn::codex_check_output "$out" "$err"
  assert_success
  assert_output sigterm

  printf '%s\n' "other" >"$err"
  run cog::fn::codex_check_output "$out" "$err"
  assert_success
  assert_output ok
}

@test "codex reset eta and resume warning parse stderr" {
  local err="${BATS_TEST_TMPDIR}/stderr.log"
  printf '%s\n' "noise" "earliest available: 2026-06-16T10:00:00Z" "warning: recovered owner" >"$err"

  run cog::fn::codex_extract_reset_eta "$err"
  assert_success
  assert_output "earliest available: 2026-06-16T10:00:00Z"

  run cog::fn::codex_resume_warning "$err"
  assert_success
  assert_output recovered-owner
}

@test "codex_classify_error covers confirmed classes" {
  local err="${BATS_TEST_TMPDIR}/stderr.log"
  local cases=(
    "1|resume-blocked|ResumeBlocked"
    "1|resume-owner-missing|ResumeOwnerMissing"
    "1|account-mismatch|owned by another account"
    "1|recovered-owner|warning: recovered owner"
    "1|resume-no-rollout|sandbox mismatch"
    "124|timeout-124|plain timeout"
    "75|quota-75|earliest available: tomorrow"
    "1|sigterm|terminated due to a signal"
    "1|nonzero|plain failure"
  )
  local item code expected body

  run cog::fn::codex_classify_error 0 "$err"
  assert_success
  assert_output ok

  for item in "${cases[@]}"; do
    code="${item%%|*}"
    expected="${item#*|}"
    expected="${expected%%|*}"
    body="${item##*|}"
    printf '%s\n' "$body" >"$err"
    run cog::fn::codex_classify_error "$code" "$err"
    assert_success
    assert_output "$expected"
  done
}

@test "codex_orientation emits read-only and write preambles" {
  run cog::fn::codex_orientation read-only
  assert_success
  [[ $output == *"STRICT READ-ONLY MODE"* ]]

  run cog::fn::codex_orientation write
  assert_success
  [[ $output == *"WRITE MODE ACTIVE"* ]]
}

@test "codex_orientation rejects invalid mode" {
  run cog::fn::codex_orientation nope

  assert_failure
}

@test "codex_explain_status emits guidance for known statuses" {
  local status
  for status in quota-75 resume-blocked timeout-124 sigterm ok; do
    run cog::fn::codex_explain_status "$status"
    assert_success
    [[ -n $output ]]
  done
}

@test "codex_explain_status rejects unknown status with known list" {
  run cog::fn::codex_explain_status bogus

  assert_failure
  [[ $output == *"known statuses"* ]]
}

@test "codex_exec_argv builds a redirection-free argv array" {
  local prompt="${BATS_TEST_TMPDIR}/p.md"
  printf 'multi\nline prompt\n' >"$prompt"
  local -a argv=()
  cog::fn::codex_exec_argv danger high "$prompt" "${BATS_TEST_TMPDIR}/o.md" argv

  [[ ${argv[0]} == "codex-session" ]]
  [[ ${argv[1]} == "exec" ]]
  # The prompt is a single argv element preserving its newlines (no shell redirection tokens).
  [[ ${argv[-1]} == $'multi\nline prompt' ]]
  printf '%s\n' "${argv[*]}" | grep -q -- "--dangerously-bypass-approvals-and-sandbox"
  printf '%s\n' "${argv[*]}" | grep -q -- "--output-last-message"
  printf '%s\n' "${argv[*]}" | grep -qv -- "2>"
}

@test "codex_exec_argv accepts xhigh and forwards unchanged" {
  local prompt="${BATS_TEST_TMPDIR}/p.md"
  printf 'prompt\n' >"$prompt"
  local -a argv=()

  cog::fn::codex_exec_argv danger xhigh "$prompt" "${BATS_TEST_TMPDIR}/o.md" argv

  printf '%s\n' "${argv[*]}" | grep -q -- "model_reasoning_effort=xhigh"
}

@test "codex_resume_argv pins the account and resumes the thread" {
  local prompt="${BATS_TEST_TMPDIR}/p.md"
  printf 'go\n' >"$prompt"
  local -a argv=()
  cog::fn::codex_resume_argv acct medium thr-1 "$prompt" "${BATS_TEST_TMPDIR}/o.md" argv

  printf '%s\n' "${argv[*]}" | grep -q -- "--account acct"
  printf '%s\n' "${argv[*]}" | grep -q -- "resume thr-1"
  [[ ${argv[-1]} == "go" ]]
}

@test "codex_reconstruct_status reads the durable events tail and output presence" {
  local events="${BATS_TEST_TMPDIR}/ev.jsonl"
  local out="${BATS_TEST_TMPDIR}/out.md"

  : >"$out"
  run cog::fn::codex_reconstruct_status "$events" "$out"
  assert_output "empty-output"

  printf '%s\n' message >"$out"
  printf '%s\n' '{"type":"thread.started"}' '{"type":"turn.completed"}' >"$events"
  run cog::fn::codex_reconstruct_status "$events" "$out"
  assert_output "ok"

  printf '%s\n' '{"type":"turn.failed"}' >"$events"
  run cog::fn::codex_reconstruct_status "$events" "$out"
  assert_output "nonzero"
}
