setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  export CODEX_FAKE_LOG="${BATS_TEST_TMPDIR}/codex-argv.log"
  export TIMEOUT_FAKE_LOG="${BATS_TEST_TMPDIR}/timeout-argv.log"
  mkdir -p "$HOME" "$XDG_STATE_HOME/codex-session" "${BATS_TEST_TMPDIR}/fakebin"
  cat >"${BATS_TEST_TMPDIR}/fakebin/codex-session" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${CODEX_FAKE_LOG}"
if [[ $* == "account current --format json" ]]; then
  printf '%s\n' '{"name":"fake-account"}'
  exit 0
fi
if [[ $* == "version" ]]; then
  if [[ ${CODEX_FAKE_VERSION_FAIL:-0} = 1 ]]; then
    exit 1
  fi
  printf '%s\n' "fake"
  exit 0
fi
out=""
prev=""
for arg in "$@"; do
  if [[ $prev == "--output-last-message" ]]; then
    out="$arg"
  fi
  prev="$arg"
done
if [[ -n $out && ${CODEX_FAKE_EMPTY:-0} != 1 ]]; then
  printf '%s\n' "${CODEX_FAKE_LAST:-last message}" >"$out"
fi
[[ -z ${CODEX_FAKE_STDERR:-} ]] || printf '%s\n' "$CODEX_FAKE_STDERR" >&2
printf '%s\n' '{"type":"thread.started","thread_id":"thread-a"}'
exit "${CODEX_FAKE_EXIT:-0}"
EOF
  cat >"${BATS_TEST_TMPDIR}/fakebin/timeout" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${TIMEOUT_FAKE_LOG}"
shift
"$@"
EOF
  chmod +x "${BATS_TEST_TMPDIR}/fakebin/codex-session" "${BATS_TEST_TMPDIR}/fakebin/timeout"
  export PATH="${BATS_TEST_TMPDIR}/fakebin:${PATH}"
  printf '%s\n' '{"thread-id":"thread-a","account":"indexed"}' >"${XDG_STATE_HOME}/codex-session/thread-index.jsonl"
  printf '%s\n' "prompt" >"${BATS_TEST_TMPDIR}/prompt.md"
}

@test "cog codex-runner renders native and fallback commands" {
  run cog codex-runner run-exec --mode native --profile medium --prompt prompt.md --output out.md --events events.jsonl --stderr stderr.log --print-command
  assert_success
  [[ $output == *"codex-session exec --profile medium --sandbox read-only --json"* ]]
  [[ $output == *"< /dev/null"* ]]
  [[ $output == *"--output-last-message"* ]]

  run cog codex-runner run-exec --mode fallback --profile medium --prompt prompt.md --output out.md --events events.jsonl --stderr stderr.log --print-command
  assert_success
  [[ $output == *"sandbox_permissions"* ]]
}

@test "cog codex-runner run-exec captures output events and thread account" {
  run cog codex-runner run-exec --mode native --profile medium --prompt "${BATS_TEST_TMPDIR}/prompt.md" --output "${BATS_TEST_TMPDIR}/out.md" --events "${BATS_TEST_TMPDIR}/events.jsonl" --stderr "${BATS_TEST_TMPDIR}/stderr.log" --thread first

  assert_success
  printf '%s\n' "$output" | jq -e '.status == "ok" and .thread_id == "thread-a" and .account == "indexed"' >/dev/null
  assert_file_contains "$CODEX_FAKE_LOG" "exec --profile medium --sandbox read-only --json"
}

@test "cog codex-runner run-resume emits resume signal" {
  export CODEX_FAKE_STDERR="warning: recovered owner"

  run cog codex-runner run-resume --account acct --thread-id thread-a --profile medium --prompt "${BATS_TEST_TMPDIR}/prompt.md" --output "${BATS_TEST_TMPDIR}/resume.md" --events "${BATS_TEST_TMPDIR}/resume.jsonl" --stderr "${BATS_TEST_TMPDIR}/resume.err"

  assert_success
  printf '%s\n' "$output" | jq -e '.resume_signal == "recovered-owner"' >/dev/null
}

@test "cog codex-runner extracts thread and classifies outputs" {
  local events="${BATS_TEST_TMPDIR}/events.jsonl"
  local out="${BATS_TEST_TMPDIR}/out.md"
  local err="${BATS_TEST_TMPDIR}/err.log"
  printf '%s\n' '{"type":"thread.started","thread_id":"first"}' '{"type":"thread.started","thread_id":"last"}' >"$events"

  run cog codex-runner extract-thread "$events" last
  assert_success
  printf '%s\n' "$output" | jq -e '.thread_id == "last"' >/dev/null

  run cog codex-runner check-output "$out" "$err"
  assert_success
  printf '%s\n' "$output" | jq -e '.status == "empty-output"' >/dev/null

  printf '%s\n' message >"$out"
  printf '%s\n' "terminated due to a signal" >"$err"
  run cog codex-runner check-output "$out" "$err"
  assert_success
  printf '%s\n' "$output" | jq -e '.status == "sigterm" and .signal == "SIGTERM"' >/dev/null
}

@test "cog codex-runner classify-error covers nonzero quota and timeout" {
  local err="${BATS_TEST_TMPDIR}/err.log"
  printf '%s\n' plain >"$err"
  run cog codex-runner classify-error 1 "$err"
  assert_success
  printf '%s\n' "$output" | jq -e '.status == "nonzero"' >/dev/null

  printf '%s\n' "earliest available: tomorrow" >"$err"
  run cog codex-runner classify-error 75 "$err"
  assert_success
  printf '%s\n' "$output" | jq -e '.status == "quota-75"' >/dev/null

  printf '%s\n' timeout >"$err"
  run cog codex-runner classify-error 124 "$err"
  assert_success
  printf '%s\n' "$output" | jq -e '.status == "timeout-124"' >/dev/null
}

@test "cog codex-runner snapshots and verifies proof" {
  local run_dir="${BATS_TEST_TMPDIR}/run"
  local pre="${BATS_TEST_TMPDIR}/pre.snap"
  local post="${BATS_TEST_TMPDIR}/post.snap"
  local diff="${BATS_TEST_TMPDIR}/diff.patch"
  local artifact="${BATS_TEST_TMPDIR}/artifact.json"
  mkdir -p "$run_dir"
  printf '%s\n' before >"${run_dir}/file.txt"

  run cog codex-runner snapshot-pre "$run_dir" "$pre"
  assert_success
  printf '%s\n' after >"${run_dir}/file.txt"
  run cog codex-runner snapshot-post "$run_dir" "$pre" "$post" "$diff"
  assert_success
  [ -s "$diff" ]

  printf '%s\n' '{"ok":true}' >"$artifact"
  run cog codex-runner verify-proof --proof "$diff" --artifact "$artifact" --require-json '.ok == true'
  assert_success

  run --separate-stderr cog codex-runner verify-proof --proof "$diff" --artifact "${BATS_TEST_TMPDIR}/missing"
  assert_failure
}

@test "cog codex-runner gate succeeds and fails closed" {
  run cog codex-runner gate codex "${BATS_TEST_TMPDIR}/gate.json"
  assert_success
  assert_output "RESOLVED ${BATS_TEST_TMPDIR}/gate.json"

  export CODEX_FAKE_VERSION_FAIL=1
  run --separate-stderr cog codex-runner gate codex "${BATS_TEST_TMPDIR}/gate-fail.json"
  assert_failure
  [[ $stderr == *"no healthy codex-session accounts"* ]]
}

@test "cog codex-runner --help dispatches" {
  run cog codex-runner --help

  assert_success
  [[ $output == *"Run codex-session orchestration"* ]]
}
