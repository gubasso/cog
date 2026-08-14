setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  export CLAUDE_FAKE_LOG="${BATS_TEST_TMPDIR}/claude-argv.log"
  mkdir -p "$HOME" "$XDG_STATE_HOME" "${BATS_TEST_TMPDIR}/fakebin"
  cat >"${BATS_TEST_TMPDIR}/fakebin/claude-session-rs" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${CLAUDE_FAKE_LOG}"
if [[ $1 == version ]]; then
  if [[ ${CLAUDE_FAKE_VERSION_FAIL:-0} = 1 ]]; then exit 1; fi
  printf '%s\n' "claude-session-rs 0.1.0"; exit 0
fi
if [[ $1 == account ]]; then
  if [[ ${CLAUDE_FAKE_AUTH_FAIL:-0} = 1 ]]; then exit 1; fi
  printf '%s\n' '{"account":"fake-account"}'; exit 0
fi
[[ -z ${CLAUDE_FAKE_STDERR:-} ]] || printf '%s\n' "$CLAUDE_FAKE_STDERR" >&2
printf '%s\n' '{"type":"system","session_id":"sess-a"}'
[[ -n ${CLAUDE_FAKE_SLEEP:-} ]] && sleep "$CLAUDE_FAKE_SLEEP"
if [[ ${CLAUDE_FAKE_EMPTY:-0} != 1 ]]; then
  printf '{"type":"result","session_id":"sess-a","result":"%s"}\n' "${CLAUDE_FAKE_RESULT:-last message}"
fi
exit "${CLAUDE_FAKE_EXIT:-0}"
EOF
  chmod +x "${BATS_TEST_TMPDIR}/fakebin/claude-session-rs"
  export PATH="${BATS_TEST_TMPDIR}/fakebin:${PATH}"
  printf '%s\n' "prompt" >"${BATS_TEST_TMPDIR}/prompt.md"
}

@test "cog claude-runner renders the read-only and write postures" {
  run cog claude-runner run-exec --access read-only --effort medium --model opus \
    --prompt "${BATS_TEST_TMPDIR}/prompt.md" --output /run/dir/out.md \
    --events /run/dir/events.jsonl --stderr /run/dir/err.log --print-command
  assert_success
  assert_output --partial -- '-- -p --model opus --effort medium'
  assert_output --partial '--permission-mode dontAsk'
  assert_output --partial 'Edit,Write,NotebookEdit'
  refute_output --partial '--dangerously-skip-permissions'

  run cog claude-runner run-exec --access write --effort high \
    --prompt "${BATS_TEST_TMPDIR}/prompt.md" --output /run/dir/out.md \
    --events /run/dir/events.jsonl --stderr /run/dir/err.log --print-command
  assert_success
  assert_output --partial '--dangerously-skip-permissions'
  refute_output --partial '--permission-mode'
}

@test "cog claude-runner passes no effort flag for the none rung" {
  run cog claude-runner run-exec --access read-only --effort none \
    --prompt "${BATS_TEST_TMPDIR}/prompt.md" --output /run/dir/out.md \
    --events /run/dir/events.jsonl --print-command
  assert_success
  refute_output --partial '--effort'
}

@test "cog claude-runner rejects an unsupported effort rung" {
  run cog claude-runner run-exec --access read-only --effort minimal \
    --prompt "${BATS_TEST_TMPDIR}/prompt.md" --output /run/dir/out.md \
    --events /run/dir/events.jsonl --print-command
  assert_failure
  assert_output --partial "invalid claude effort"
}

@test "cog claude-runner rejects an invalid access" {
  run cog claude-runner run-exec --access sandbox --effort medium \
    --prompt "${BATS_TEST_TMPDIR}/prompt.md" --output /run/dir/out.md \
    --events /run/dir/events.jsonl --print-command
  assert_failure
  assert_output --partial "invalid run-exec access"
}

@test "cog claude-runner passes the account and profile to the wrapper prefix" {
  run cog claude-runner run-exec --access read-only --effort low \
    --account work --profile default \
    --prompt "${BATS_TEST_TMPDIR}/prompt.md" --output /run/dir/out.md \
    --events /run/dir/events.jsonl --print-command
  assert_success
  assert_output --partial 'claude-session-rs --account work --profile default --'
}

@test "cog claude-runner launches a durable job and finalize extracts the result" {
  local run_dir="${BATS_TEST_TMPDIR}/run"
  mkdir -p "$run_dir"
  export CLAUDE_FAKE_RESULT="the final answer"
  run cog claude-runner run-exec --access write --effort medium --model opus \
    --prompt "${BATS_TEST_TMPDIR}/prompt.md" \
    --output "${run_dir}/out.md" --events "${run_dir}/events.jsonl" \
    --stderr "${run_dir}/err.log" --state "${run_dir}/job.longrun.json"
  assert_success
  assert_output --partial "STATE_FILE=${run_dir}/job.longrun.json"
  assert_file_exists "${run_dir}/job.longrun.json"
  jq -e '.engine == "claude" and .engine_meta.access == "write" and .engine_meta.model == "opus"' \
    "${run_dir}/job.longrun.json"

  run cog claude-runner finalize --state "${run_dir}/job.longrun.json" --max-wall 30
  assert_success
  jq -e '.action == "run-exec" and .ok == true and .status == "ok" and .session_id == "sess-a"' <<<"$output"
  assert_file_contains "${run_dir}/out.md" "the final answer"
  jq -e '.state == "finalized-ok"' "${run_dir}/job.longrun.json"
}

@test "cog claude-runner creates no durable state file when a version precondition fails" {
  local run_dir="${BATS_TEST_TMPDIR}/run"
  mkdir -p "$run_dir"
  CLAUDE_FAKE_VERSION_FAIL=1 run cog claude-runner run-exec --access read-only --effort low \
    --prompt "${BATS_TEST_TMPDIR}/prompt.md" \
    --output "${run_dir}/out.md" --events "${run_dir}/events.jsonl" \
    --state "${run_dir}/job.longrun.json"
  assert_failure
  assert_output --partial "claude-session is not healthy"
  [ ! -e "${run_dir}/job.longrun.json" ]
  [ ! -e "${run_dir}/events.jsonl" ]
}

@test "cog claude-runner creates no durable state file when no account is bound" {
  local run_dir="${BATS_TEST_TMPDIR}/run"
  mkdir -p "$run_dir"
  export CLAUDE_FAKE_AUTH_FAIL=1
  run cog claude-runner run-exec --access read-only --effort low \
    --prompt "${BATS_TEST_TMPDIR}/prompt.md" \
    --output "${run_dir}/out.md" --events "${run_dir}/events.jsonl" \
    --state "${run_dir}/job.longrun.json"
  assert_failure
  assert_output --partial "no bound claude-session account"
  [ ! -e "${run_dir}/job.longrun.json" ]
}

@test "cog claude-runner requires absolute artifact paths" {
  run cog claude-runner run-exec --access read-only --effort low \
    --prompt "${BATS_TEST_TMPDIR}/prompt.md" \
    --output out.md --events "${BATS_TEST_TMPDIR}/events.jsonl" \
    --state "${BATS_TEST_TMPDIR}/job.longrun.json"
  assert_failure
  assert_output --partial "claude-runner artifact path must be absolute"
  [ ! -e "${BATS_TEST_TMPDIR}/job.longrun.json" ]
}

@test "cog claude-runner rejects artifact paths that alias each other" {
  # The four artifacts are independent sinks; --state equal to --output lets the
  # extracted result truncate the durable state the caller polls.
  local st="${BATS_TEST_TMPDIR}/alias.longrun.json"
  run cog claude-runner run-exec --access read-only --effort low \
    --prompt "${BATS_TEST_TMPDIR}/prompt.md" \
    --output "$st" --events "${BATS_TEST_TMPDIR}/alias.jsonl" --state "$st"
  assert_failure
  assert_output --partial "claude-runner artifact paths must be distinct"
  [ ! -e "$st" ]

  run cog claude-runner run-exec --access read-only --effort low \
    --prompt "${BATS_TEST_TMPDIR}/prompt.md" \
    --output "${BATS_TEST_TMPDIR}/a.out" --events "${BATS_TEST_TMPDIR}/both.log" \
    --stderr "${BATS_TEST_TMPDIR}/both.log" --state "${BATS_TEST_TMPDIR}/alias2.longrun.json"
  assert_failure
  assert_output --partial "claude-runner artifact paths must be distinct"
}

@test "cog claude-runner creates a run directory that does not exist yet" {
  # The preflight fragment is the first write into the run dir and it lands
  # before the durable job, so the runner must create the directory the
  # launcher would otherwise have made.
  local dir="${BATS_TEST_TMPDIR}/fresh/nested"
  run cog claude-runner run-exec --access read-only --effort low \
    --prompt "${BATS_TEST_TMPDIR}/prompt.md" \
    --output "${dir}/o.md" --events "${dir}/ev.jsonl" --state "${dir}/j.longrun.json"
  assert_success
  assert_output --partial "STATE_FILE=${dir}/j.longrun.json"
  [ -e "${dir}/j.longrun.json" ]
}

@test "cog claude-runner guards an output that collides with a prompt artifact write" {
  local run_dir="${BATS_TEST_TMPDIR}/run"
  mkdir -p "$run_dir"
  printf '%s\n' "\$review-plan-oneshot --output ${run_dir}/prepared-plan.md" >"${run_dir}/prompt.md"
  run cog claude-runner run-exec --access write --effort low \
    --prompt "${run_dir}/prompt.md" \
    --output "${run_dir}/prepared-plan.md" --events "${run_dir}/events.jsonl" \
    --state "${run_dir}/job.longrun.json"
  assert_failure
  assert_output --partial "collides"
  assert_output --partial "claude-output.md"
}

@test "cog claude-runner defaults the durable-job cwd to the git repo root" {
  local repo="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "${repo}/nested" "${BATS_TEST_TMPDIR}/run"
  git init -q "$repo"
  cd "${repo}/nested"
  run cog claude-runner run-exec --access read-only --effort low \
    --prompt "${BATS_TEST_TMPDIR}/prompt.md" \
    --output "${BATS_TEST_TMPDIR}/run/out.md" --events "${BATS_TEST_TMPDIR}/run/events.jsonl" \
    --state "${BATS_TEST_TMPDIR}/run/job.longrun.json"
  assert_success
  jq -e --arg repo "$repo" '.cwd == $repo' "${BATS_TEST_TMPDIR}/run/job.longrun.json"
}

@test "cog claude-runner finalize reports a still-running job with exit 75" {
  local run_dir="${BATS_TEST_TMPDIR}/run"
  mkdir -p "$run_dir"
  export CLAUDE_FAKE_SLEEP=5
  run cog claude-runner run-exec --access read-only --effort low \
    --prompt "${BATS_TEST_TMPDIR}/prompt.md" \
    --output "${run_dir}/out.md" --events "${run_dir}/events.jsonl" \
    --state "${run_dir}/job.longrun.json"
  assert_success

  # GR4: not done, not failed — signal EX_TEMPFAIL (75); the live job is never classified.
  run --separate-stderr cog claude-runner finalize --state "${run_dir}/job.longrun.json"
  [ "$status" -eq 75 ]
  printf '%s\n' "$output" | jq -e '.state == "running" and .ok == false' >/dev/null
  [[ $stderr == *"still running"* ]]

  run cog longrun cancel --state "${run_dir}/job.longrun.json" --signal KILL
  assert_success
}

@test "cog claude-runner finalize classifies a failed job from the exit code alone" {
  local run_dir="${BATS_TEST_TMPDIR}/run"
  mkdir -p "$run_dir"
  export CLAUDE_FAKE_EXIT=1
  run cog claude-runner run-exec --access read-only --effort low \
    --prompt "${BATS_TEST_TMPDIR}/prompt.md" \
    --output "${run_dir}/out.md" --events "${run_dir}/events.jsonl" \
    --state "${run_dir}/job.longrun.json"
  assert_success

  run --separate-stderr cog claude-runner finalize --state "${run_dir}/job.longrun.json" --max-wall 30
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | jq -e '.ok == false and .status == "nonzero" and .exit_code == 1' >/dev/null
}

@test "cog claude-runner finalize reports an empty output as a failure" {
  local run_dir="${BATS_TEST_TMPDIR}/run"
  mkdir -p "$run_dir"
  export CLAUDE_FAKE_EMPTY=1
  run cog claude-runner run-exec --access read-only --effort low \
    --prompt "${BATS_TEST_TMPDIR}/prompt.md" \
    --output "${run_dir}/out.md" --events "${run_dir}/events.jsonl" \
    --state "${run_dir}/job.longrun.json"
  assert_success

  run --separate-stderr cog claude-runner finalize --state "${run_dir}/job.longrun.json" --max-wall 30
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | jq -e '.ok == false and .status == "empty-output"' >/dev/null
}

@test "cog claude-runner gate succeeds and fails closed" {
  run cog claude-runner gate "${BATS_TEST_TMPDIR}/preflight.json"
  assert_success
  jq -e '.claude_session.available == true and .claude_session.auth == "ok"' "${BATS_TEST_TMPDIR}/preflight.json"

  export CLAUDE_FAKE_VERSION_FAIL=1
  run cog claude-runner gate "${BATS_TEST_TMPDIR}/preflight2.json"
  assert_failure
}

@test "cog claude-runner --help dispatches" {
  run cog claude-runner --help
  assert_success
  assert_output --partial "cog claude-runner run-exec"
}
