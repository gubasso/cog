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
[[ -n ${CODEX_FAKE_SLEEP:-} ]] && sleep "$CODEX_FAKE_SLEEP"
printf '%s\n' '{"type":"turn.completed"}'
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
  run cog codex-runner run-exec --mode native --effort medium --prompt prompt.md --output out.md --events events.jsonl --stderr stderr.log --print-command
  assert_success
  [[ $output == *"codex-session exec -c model_reasoning_effort=medium --sandbox read-only --json"* ]]
  [[ $output == *"< /dev/null"* ]]
  [[ $output == *"--output-last-message"* ]]

  run cog codex-runner run-exec --mode fallback --effort medium --prompt prompt.md --output out.md --events events.jsonl --stderr stderr.log --print-command
  assert_success
  [[ $output == *"sandbox_permissions"* ]]
}

@test "cog codex-runner run-exec launches a durable job; finalize captures output, events, thread account" {
  local st="${BATS_TEST_TMPDIR}/stage1.longrun.json"
  run cog codex-runner run-exec --mode native --effort medium --prompt "${BATS_TEST_TMPDIR}/prompt.md" --output "${BATS_TEST_TMPDIR}/out.md" --events "${BATS_TEST_TMPDIR}/events.jsonl" --stderr "${BATS_TEST_TMPDIR}/stderr.log" --thread first --state "$st"
  assert_success
  [[ $output == *"STATE_FILE=${st}"* ]]

  run cog codex-runner finalize --state "$st" --max-wall 30
  assert_success
  printf '%s\n' "$output" | jq -e '.action == "run-exec" and .status == "ok" and .thread_id == "thread-a" and .account == "indexed" and .effort == "medium" and .access == "read-only"' >/dev/null
  assert_file_contains "$CODEX_FAKE_LOG" "exec -c model_reasoning_effort=medium --sandbox read-only --json"
}

@test "cog codex-runner run-exec defaults the durable-job cwd to the git repo root" {
  # Codex exec refuses in a non-git, non-trusted dir; the job must launch from
  # the project repo root, not whatever scratch dir the observer sat in.
  local repo="${BATS_TEST_TMPDIR}/gitproj"
  mkdir -p "$repo/sub"
  git -C "$repo" init -q
  local root
  root="$(git -C "$repo" rev-parse --show-toplevel)"
  local st="${BATS_TEST_TMPDIR}/cwd-default.longrun.json"
  cd "$repo/sub"
  run cog codex-runner run-exec --mode native --effort medium --prompt "${BATS_TEST_TMPDIR}/prompt.md" --output "${BATS_TEST_TMPDIR}/cwd-default.out" --events "${BATS_TEST_TMPDIR}/cwd-default.jsonl" --stderr "${BATS_TEST_TMPDIR}/cwd-default.err" --state "$st"
  assert_success
  jq -e --arg c "$root" '.cwd == $c' "$st" >/dev/null
}

@test "cog codex-runner run-exec honors an explicit --cwd override" {
  local repo="${BATS_TEST_TMPDIR}/explicit-proj"
  mkdir -p "$repo"
  local st="${BATS_TEST_TMPDIR}/cwd-explicit.longrun.json"
  run cog codex-runner run-exec --mode native --effort medium --prompt "${BATS_TEST_TMPDIR}/prompt.md" --output "${BATS_TEST_TMPDIR}/cwd-explicit.out" --events "${BATS_TEST_TMPDIR}/cwd-explicit.jsonl" --stderr "${BATS_TEST_TMPDIR}/cwd-explicit.err" --cwd "$repo" --state "$st"
  assert_success
  jq -e --arg c "$repo" '.cwd == $c' "$st" >/dev/null
}

@test "cog codex-runner run-resume honors an explicit --cwd override" {
  local repo="${BATS_TEST_TMPDIR}/resume-proj"
  mkdir -p "$repo"
  local st="${BATS_TEST_TMPDIR}/cwd-resume.longrun.json"
  run cog codex-runner run-resume --account acct --thread-id thread-a --effort medium --prompt "${BATS_TEST_TMPDIR}/prompt.md" --output "${BATS_TEST_TMPDIR}/cwd-resume.out" --events "${BATS_TEST_TMPDIR}/cwd-resume.jsonl" --stderr "${BATS_TEST_TMPDIR}/cwd-resume.err" --cwd "$repo" --state "$st"
  assert_success
  jq -e --arg c "$repo" '.cwd == $c' "$st" >/dev/null
}

@test "cog codex-runner run-exec enforces write access coherence" {
  local mode
  for mode in native fallback quick-auto; do
    rm -f "$CODEX_FAKE_LOG"
    local stderr_args=()
    if [[ $mode == native || $mode == fallback ]]; then
      stderr_args=(--stderr "${BATS_TEST_TMPDIR}/${mode}.stderr")
    fi
    run --separate-stderr cog codex-runner run-exec --mode "$mode" --access write --effort medium --prompt "${BATS_TEST_TMPDIR}/prompt.md" --output "${BATS_TEST_TMPDIR}/${mode}.out" --events "${BATS_TEST_TMPDIR}/${mode}.jsonl" "${stderr_args[@]}"

    assert_failure
    [[ $stderr == *"write access requires a write-capable mode"* ]]
    [ ! -e "$CODEX_FAKE_LOG" ]
  done

  local stw="${BATS_TEST_TMPDIR}/danger-write.longrun.json"
  run cog codex-runner run-exec --mode danger --access write --effort medium --prompt "${BATS_TEST_TMPDIR}/prompt.md" --output "${BATS_TEST_TMPDIR}/danger.out" --events "${BATS_TEST_TMPDIR}/danger.jsonl" --state "$stw"
  assert_success
  run cog codex-runner finalize --state "$stw" --max-wall 30
  assert_success
  printf '%s\n' "$output" | jq -e '.access == "write" and .status == "ok"' >/dev/null

  local str="${BATS_TEST_TMPDIR}/danger-read.longrun.json"
  run cog codex-runner run-exec --mode danger --access read-only --effort medium --prompt "${BATS_TEST_TMPDIR}/prompt.md" --output "${BATS_TEST_TMPDIR}/danger-read.out" --events "${BATS_TEST_TMPDIR}/danger-read.jsonl" --state "$str"
  assert_success
  run cog codex-runner finalize --state "$str" --max-wall 30
  assert_success
  printf '%s\n' "$output" | jq -e '.access == "read-only" and .status == "ok"' >/dev/null
}

@test "cog codex-runner run-exec rejects invalid access" {
  run --separate-stderr cog codex-runner run-exec --mode danger --access bogus --effort medium --prompt "${BATS_TEST_TMPDIR}/prompt.md" --output "${BATS_TEST_TMPDIR}/bogus.out" --events "${BATS_TEST_TMPDIR}/bogus.jsonl"

  assert_failure
  [[ $stderr == *"invalid run-exec access"* ]]
}

@test "cog codex-runner run-resume finalize emits resume signal" {
  export CODEX_FAKE_STDERR="warning: recovered owner"
  local st="${BATS_TEST_TMPDIR}/resume.longrun.json"

  run cog codex-runner run-resume --account acct --thread-id thread-a --effort medium --prompt "${BATS_TEST_TMPDIR}/prompt.md" --output "${BATS_TEST_TMPDIR}/resume.md" --events "${BATS_TEST_TMPDIR}/resume.jsonl" --stderr "${BATS_TEST_TMPDIR}/resume.err" --state "$st"
  assert_success

  run cog codex-runner finalize --state "$st" --max-wall 30
  assert_success
  printf '%s\n' "$output" | jq -e '.action == "run-resume" and .resume_signal == "recovered-owner" and .effort == "medium" and .thread_id == "thread-a"' >/dev/null
}

@test "cog codex-runner run-exec requires --state" {
  run --separate-stderr cog codex-runner run-exec --mode danger --access write --effort medium --prompt "${BATS_TEST_TMPDIR}/prompt.md" --output "${BATS_TEST_TMPDIR}/ns.out" --events "${BATS_TEST_TMPDIR}/ns.jsonl"
  assert_failure
  [[ $stderr == *"missing --state"* ]]
}

@test "cog codex-runner finalize reports a still-running job with exit 75 and never classifies it" {
  export CODEX_FAKE_SLEEP=5
  local st="${BATS_TEST_TMPDIR}/slow.longrun.json"
  run cog codex-runner run-exec --mode danger --access write --effort medium --prompt "${BATS_TEST_TMPDIR}/prompt.md" --output "${BATS_TEST_TMPDIR}/slow.out" --events "${BATS_TEST_TMPDIR}/slow.jsonl" --state "$st"
  assert_success

  # GR4: not done, not failed — signal EX_TEMPFAIL (75); the live job is never classified.
  run --separate-stderr cog codex-runner finalize --state "$st"
  [ "$status" -eq 75 ]
  printf '%s\n' "$output" | jq -e '.state == "running" and .ok == false' >/dev/null
  [[ $stderr == *"still running"* ]]
  cog codex-runner cancel --state "$st" >/dev/null
}

@test "cog codex-runner finalize signals a failed codex job with exit 1" {
  export CODEX_FAKE_EXIT=1
  local st="${BATS_TEST_TMPDIR}/fail.longrun.json"
  run cog codex-runner run-exec --mode danger --access write --effort medium --prompt "${BATS_TEST_TMPDIR}/prompt.md" --output "${BATS_TEST_TMPDIR}/fail.out" --events "${BATS_TEST_TMPDIR}/fail.jsonl" --state "$st"
  assert_success

  # GR4: a finished-but-failed job signals exit 1; the body carries the classified status.
  run --separate-stderr cog codex-runner finalize --state "$st" --max-wall 30
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | jq -e '.action == "run-exec" and .ok == false and .status == "nonzero" and .exit_code == 1' >/dev/null
}

@test "cog codex-runner run-exec rejects legacy --profile" {
  run --separate-stderr cog codex-runner run-exec --mode native --profile medium --prompt "${BATS_TEST_TMPDIR}/prompt.md" --output "${BATS_TEST_TMPDIR}/out.md" --events "${BATS_TEST_TMPDIR}/events.jsonl" --stderr "${BATS_TEST_TMPDIR}/stderr.log"

  assert_failure
  [[ $stderr == *"invalid run-exec argument"* ]]
}

@test "cog codex-runner run-resume rejects legacy --profile" {
  run --separate-stderr cog codex-runner run-resume --account acct --thread-id thread-a --profile medium --prompt "${BATS_TEST_TMPDIR}/prompt.md" --output "${BATS_TEST_TMPDIR}/resume.md" --events "${BATS_TEST_TMPDIR}/resume.jsonl" --stderr "${BATS_TEST_TMPDIR}/resume.err"

  assert_failure
  [[ $stderr == *"invalid run-resume argument"* ]]
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
