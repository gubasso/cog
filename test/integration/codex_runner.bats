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
if [[ $1 == account ]]; then
  if [[ ${CODEX_FAKE_AUTH_FAIL:-0} = 1 ]]; then
    exit 1
  fi
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

@test "cog codex-runner run-exec launches a durable job; finalize captures output, events, thread account" {
  local st="${BATS_TEST_TMPDIR}/job.longrun.json"
  run cog codex-runner run-exec --mode native --effort medium --prompt "${BATS_TEST_TMPDIR}/prompt.md" --output "${BATS_TEST_TMPDIR}/out.md" --events "${BATS_TEST_TMPDIR}/events.jsonl" --stderr "${BATS_TEST_TMPDIR}/stderr.log" --thread first --state "$st"
  assert_success
  [[ $output == *"STATE_FILE=${st}"* ]]
  jq -e --arg out "${BATS_TEST_TMPDIR}/out.md" --arg prompt "${BATS_TEST_TMPDIR}/prompt.md" \
    --arg events "${BATS_TEST_TMPDIR}/events.jsonl" --arg stderr "${BATS_TEST_TMPDIR}/stderr.log" \
    '.engine_meta.mode == "native" and .engine_meta.access == "read-only" and
      .engine_meta.effort == "medium" and .engine_meta.thread_selection == "first" and
      (.engine_meta.command | contains("codex-session exec -c model_reasoning_effort=medium --sandbox read-only --json")) and
      (.engine_meta.command | contains("--output-last-message \"" + $out + "\"")) and
      (.engine_meta.command | contains("\"$(cat \"" + $prompt + "\")\"")) and
      (.engine_meta.command | contains("> \"" + $events + "\"")) and
      (.engine_meta.command | contains("2> \"" + $stderr + "\""))' "$st" >/dev/null

  run cog codex-runner finalize --state "$st" --max-wall 30
  assert_success
  printf '%s\n' "$output" | jq -e '.action == "run-exec" and .status == "ok" and .thread_id == "thread-a" and .account == "indexed" and .effort == "medium" and .access == "read-only"' >/dev/null
  assert_file_contains "$CODEX_FAKE_LOG" "exec -c model_reasoning_effort=medium --sandbox read-only --json"
}

@test "cog codex-runner fallback records command metadata and actual provider argv" {
  local st="${BATS_TEST_TMPDIR}/fallback.longrun.json"
  run cog codex-runner run-exec --mode fallback --effort high \
    --prompt "${BATS_TEST_TMPDIR}/prompt.md" --output "${BATS_TEST_TMPDIR}/fallback.out" \
    --events "${BATS_TEST_TMPDIR}/fallback.jsonl" --stderr "${BATS_TEST_TMPDIR}/fallback.err" --state "$st"
  assert_success
  jq -e '.engine_meta.mode == "fallback" and .engine_meta.effort == "high" and
    (.engine_meta.command | contains("model_reasoning_effort=high")) and
    (.engine_meta.command | contains("sandbox_permissions=[\"disk-full-read-access\"]")) and
    (.engine_meta.command | contains("--sandbox read-only") | not)' "$st" >/dev/null

  run cog codex-runner finalize --state "$st" --max-wall 30
  assert_success
  grep -F -- 'exec -c model_reasoning_effort=high -c sandbox_permissions=["disk-full-read-access"] --json' "$CODEX_FAKE_LOG" >/dev/null
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
  run cog codex-runner finalize --state "$st" --max-wall 30
  assert_success
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
  grep -F -- "--account acct exec -c model_reasoning_effort=medium resume thread-a -c sandbox_mode=read-only --json --output-last-message ${BATS_TEST_TMPDIR}/resume.md prompt" "$CODEX_FAKE_LOG" >/dev/null
}

@test "cog codex-runner run-resume defaults to read-only and records the access it ran under" {
  local st="${BATS_TEST_TMPDIR}/resume-ro.longrun.json"
  run cog codex-runner run-resume --account acct --thread-id thread-a --effort medium --prompt "${BATS_TEST_TMPDIR}/prompt.md" --output "${BATS_TEST_TMPDIR}/resume-ro.md" --events "${BATS_TEST_TMPDIR}/resume-ro.jsonl" --stderr "${BATS_TEST_TMPDIR}/resume-ro.err" --state "$st"
  assert_success
  jq -e '.engine_meta.access == "read-only" and (.engine_meta.command | contains("sandbox_mode=read-only")) and (.engine_meta.command | contains("dangerously-bypass") | not)' "$st" >/dev/null

  run cog codex-runner finalize --state "$st" --max-wall 30
  assert_success
  printf '%s\n' "$output" | jq -e '.access == "read-only"' >/dev/null
  grep -F -- "--account acct exec -c model_reasoning_effort=medium resume thread-a -c sandbox_mode=read-only --json --output-last-message ${BATS_TEST_TMPDIR}/resume-ro.md prompt" "$CODEX_FAKE_LOG" >/dev/null
}

@test "cog codex-runner run-resume bypasses the sandbox only on explicit write access" {
  local st="${BATS_TEST_TMPDIR}/resume-rw.longrun.json"
  run cog codex-runner run-resume --account acct --thread-id thread-a --access write --effort medium --prompt "${BATS_TEST_TMPDIR}/prompt.md" --output "${BATS_TEST_TMPDIR}/resume-rw.md" --events "${BATS_TEST_TMPDIR}/resume-rw.jsonl" --stderr "${BATS_TEST_TMPDIR}/resume-rw.err" --state "$st"
  assert_success
  jq -e '.engine_meta.access == "write" and (.engine_meta.command | contains("--dangerously-bypass-approvals-and-sandbox"))' "$st" >/dev/null

  run cog codex-runner finalize --state "$st" --max-wall 30
  assert_success
  printf '%s\n' "$output" | jq -e '.access == "write"' >/dev/null
  grep -F -- "--account acct exec -c model_reasoning_effort=medium resume thread-a --dangerously-bypass-approvals-and-sandbox --json --output-last-message ${BATS_TEST_TMPDIR}/resume-rw.md prompt" "$CODEX_FAKE_LOG" >/dev/null
}

@test "cog codex-runner run-resume rejects invalid access" {
  run --separate-stderr cog codex-runner run-resume --account acct --thread-id thread-a --access bogus --effort medium --prompt "${BATS_TEST_TMPDIR}/prompt.md" --output "${BATS_TEST_TMPDIR}/resume-bogus.md" --events "${BATS_TEST_TMPDIR}/resume-bogus.jsonl" --state "${BATS_TEST_TMPDIR}/resume-bogus.longrun.json"

  assert_failure
  [[ $stderr == *"invalid run-resume access"* ]]
}

@test "cog codex-runner run-exec requires --state" {
  run --separate-stderr cog codex-runner run-exec --mode danger --access write --effort medium --prompt "${BATS_TEST_TMPDIR}/prompt.md" --output "${BATS_TEST_TMPDIR}/ns.out" --events "${BATS_TEST_TMPDIR}/ns.jsonl"
  assert_failure
  [[ $stderr == *"missing --state"* ]]
}

@test "cog codex-runner run-exec rejects a relative artifact path and leaves no cwd leftovers" {
  local leak="${BATS_TEST_TMPDIR}/leakdir"
  mkdir -p "$leak"
  cd "$leak"
  run --separate-stderr cog codex-runner run-exec --mode fallback --effort medium --prompt "${BATS_TEST_TMPDIR}/prompt.md" --output codex-out.txt --events codex-events.jsonl --stderr codex-stderr.txt --state codex-state.json
  assert_failure
  [[ $stderr == *"artifact path must be absolute"* ]]
  [[ ! -e "${leak}/codex-out.txt" ]]
  [[ ! -e "${leak}/codex-events.jsonl" ]]
  [[ ! -e "${leak}/codex-state.done" ]]
  [[ ! -e "${leak}/codex-state.exit" ]]
}

@test "cog codex-runner run-resume rejects a relative artifact path" {
  run --separate-stderr cog codex-runner run-resume --account acct --thread-id thread-a --effort medium --prompt "${BATS_TEST_TMPDIR}/prompt.md" --output codex-out.txt --events codex-events.jsonl --stderr codex-stderr.txt --state codex-state.json
  assert_failure
  [[ $stderr == *"artifact path must be absolute"* ]]
}

@test "cog codex-runner run-exec creates no durable state file when a precondition fails" {
  # ADR-0031: preconditions are checked before the durable job exists, so a
  # failure here costs no state file and no run-directory artifacts.
  local st="${BATS_TEST_TMPDIR}/pre.longrun.json"
  CODEX_FAKE_VERSION_FAIL=1 run --separate-stderr cog codex-runner run-exec --mode danger --access write --effort medium --prompt "${BATS_TEST_TMPDIR}/prompt.md" --output "${BATS_TEST_TMPDIR}/pre.out" --events "${BATS_TEST_TMPDIR}/pre.jsonl" --state "$st"
  assert_failure
  [[ $stderr == *"codex-session is not healthy"* ]]
  [[ ! -e $st ]]
  [[ ! -e "${BATS_TEST_TMPDIR}/pre.jsonl" ]]
}

@test "cog codex-runner run-exec creates no durable state file when no account is bound" {
  # ADR-0031 names the credential alongside the binary and the version: a
  # wrapper that runs but has nothing to authenticate with cannot launch, and
  # after launch that failure is indistinguishable from an agent exit.
  local st="${BATS_TEST_TMPDIR}/auth.longrun.json"
  CODEX_FAKE_AUTH_FAIL=1 run --separate-stderr cog codex-runner run-exec --mode native --effort medium --prompt "${BATS_TEST_TMPDIR}/prompt.md" --output "${BATS_TEST_TMPDIR}/auth.out" --events "${BATS_TEST_TMPDIR}/auth.jsonl" --stderr "${BATS_TEST_TMPDIR}/auth.err" --state "$st"
  assert_failure
  [[ $stderr == *"no bound codex-session account"* ]]
  [[ ! -e $st ]]
  [[ ! -e "${BATS_TEST_TMPDIR}/auth.jsonl" ]]
}

@test "cog codex-runner run-exec rejects artifact paths that alias each other" {
  # The four artifacts are independent sinks handed to longrun::start; sharing
  # one path makes the writes clobber each other, and --state equal to --output
  # destroys the durable state the caller polls.
  local st="${BATS_TEST_TMPDIR}/alias.longrun.json"
  run --separate-stderr cog codex-runner run-exec --mode native --effort medium --prompt "${BATS_TEST_TMPDIR}/prompt.md" --output "$st" --events "${BATS_TEST_TMPDIR}/alias.jsonl" --stderr "${BATS_TEST_TMPDIR}/alias.err" --state "$st"
  assert_failure
  [[ $stderr == *"artifact paths must be distinct"* ]]
  [[ ! -e $st ]]

  run --separate-stderr cog codex-runner run-exec --mode native --effort medium --prompt "${BATS_TEST_TMPDIR}/prompt.md" --output "${BATS_TEST_TMPDIR}/a.out" --events "${BATS_TEST_TMPDIR}/both.log" --stderr "${BATS_TEST_TMPDIR}/both.log" --state "${BATS_TEST_TMPDIR}/alias2.longrun.json"
  assert_failure
  [[ $stderr == *"artifact paths must be distinct"* ]]
}

@test "cog codex-runner run-exec creates a run directory that does not exist yet" {
  # The preflight fragment is the first write into the run dir and it lands
  # before the durable job, so the runner must create the directory the
  # launcher would otherwise have made.
  local dir="${BATS_TEST_TMPDIR}/fresh/nested"
  run cog codex-runner run-exec --mode native --effort medium --prompt "${BATS_TEST_TMPDIR}/prompt.md" --output "${dir}/o.md" --events "${dir}/ev.jsonl" --stderr "${dir}/e.log" --state "${dir}/j.longrun.json"
  assert_success
  assert_output --partial "STATE_FILE=${dir}/j.longrun.json"
  [[ -e "${dir}/j.longrun.json" ]]
  run cog codex-runner finalize --state "${dir}/j.longrun.json" --max-wall 30
  assert_success
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
  [[ $stderr == *"codex-session is not healthy"* ]]
}

@test "cog codex-runner --help dispatches" {
  run cog codex-runner --help

  assert_success
  [[ $output == *"Run codex-session orchestration"* ]]
}

@test "cog codex-runner run-exec pins a model only when --model is passed" {
  local st="${BATS_TEST_TMPDIR}/model.longrun.json"
  run cog codex-runner run-exec --mode native --effort medium --model gpt-5.5 --prompt "${BATS_TEST_TMPDIR}/prompt.md" --output "${BATS_TEST_TMPDIR}/model.out" --events "${BATS_TEST_TMPDIR}/model.jsonl" --stderr "${BATS_TEST_TMPDIR}/model.err" --state "$st"
  assert_success
  jq -e '.engine_meta.model == "gpt-5.5" and
    (.engine_meta.command | contains("exec -c model=gpt-5.5 -c model_reasoning_effort=medium"))' "$st" >/dev/null
  run cog codex-runner finalize --state "$st" --max-wall 30
  assert_success
  assert_file_contains "$CODEX_FAKE_LOG" "exec -c model=gpt-5.5 -c model_reasoning_effort=medium"

  # Omitted --model means the harness default: no model config reaches the CLI.
  local st2="${BATS_TEST_TMPDIR}/nomodel.longrun.json"
  run cog codex-runner run-exec --mode native --effort medium --prompt "${BATS_TEST_TMPDIR}/prompt.md" --output "${BATS_TEST_TMPDIR}/nomodel.out" --events "${BATS_TEST_TMPDIR}/nomodel.jsonl" --stderr "${BATS_TEST_TMPDIR}/nomodel.err" --state "$st2"
  assert_success
  jq -e '.engine_meta.model == "" and
    (.engine_meta.command | contains("-c model=") | not)' "$st2" >/dev/null
}

@test "cog codex-runner run-resume pins a model only when --model is passed" {
  local st="${BATS_TEST_TMPDIR}/resume-model.longrun.json"
  run cog codex-runner run-resume --account acct --thread-id thread-a --effort medium --model gpt-5.5 --prompt "${BATS_TEST_TMPDIR}/prompt.md" --output "${BATS_TEST_TMPDIR}/resume-model.md" --events "${BATS_TEST_TMPDIR}/resume-model.jsonl" --stderr "${BATS_TEST_TMPDIR}/resume-model.err" --state "$st"
  assert_success
  jq -e '.engine_meta.model == "gpt-5.5" and
    (.engine_meta.command | contains("exec -c model=gpt-5.5 -c model_reasoning_effort=medium resume"))' "$st" >/dev/null
  run cog codex-runner finalize --state "$st" --max-wall 30
  assert_success
  assert_file_contains "$CODEX_FAKE_LOG" "exec -c model=gpt-5.5 -c model_reasoning_effort=medium resume thread-a"
}
