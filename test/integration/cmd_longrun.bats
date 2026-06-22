setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  mkdir -p "$HOME" "$XDG_STATE_HOME"
  RD="${BATS_TEST_TMPDIR}/run"
  mkdir -p "$RD"
}

@test "cog longrun start returns immediately and the job runs detached" {
  local st="${RD}/j.longrun.json"
  run cog longrun start --label j --state "$st" -- bash -c 'sleep 3; echo done'
  assert_success
  [[ $output == *"STATE_FILE=${st}"* ]]
  [[ $output == *"JOB_PGID="* ]]

  # The start call already returned; the job is still executing independently.
  run cog longrun status --state "$st" --json
  assert_success
  printf '%s\n' "$output" | jq -e '.state == "running" and .alive == true' >/dev/null
}

@test "cog longrun finalize is bounded and signals a still-running job with exit 75" {
  local st="${RD}/w.longrun.json"
  cog longrun start --label w --state "$st" -- bash -c 'sleep 5' >/dev/null

  # GR4: a still-running job is not done, not failed — it signals EX_TEMPFAIL (75).
  run --separate-stderr cog longrun finalize --state "$st" --max-wall 1 --poll 1
  [ "$status" -eq 75 ]
  printf '%s\n' "$output" | jq -e '.state == "running" and .ok == false' >/dev/null
}

@test "cog longrun finalize polls to finalized-ok (exit 0) and is idempotent" {
  local st="${RD}/ok.longrun.json"
  cog longrun start --label ok --state "$st" -- bash -c 'printf hi; exit 0' >/dev/null

  run cog longrun finalize --state "$st" --max-wall 30
  assert_success
  printf '%s\n' "$output" | jq -e '.state == "finalized-ok" and .ok == true and .exit_code == 0 and .exit_source == "wrapper"' >/dev/null

  local first="$output"
  run cog longrun finalize --state "$st"
  assert_success
  [ "$output" = "$first" ]
}

@test "cog longrun finalize maps a non-zero exit to finalized-failed (exit 1)" {
  local st="${RD}/bad.longrun.json"
  cog longrun start --label bad --state "$st" -- bash -c 'exit 3' >/dev/null

  run --separate-stderr cog longrun finalize --state "$st" --max-wall 30
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | jq -e '.state == "finalized-failed" and .ok == false and .exit_code == 3' >/dev/null
}

@test "cog longrun finalize reconstructs lost when the wrapper is killed (exit 1)" {
  local st="${RD}/lost.longrun.json"
  cog longrun start --label lost --state "$st" -- bash -c 'sleep 30' >/dev/null
  local pgid
  pgid="$(jq -r '.pgid' "$st")"
  kill -KILL -"$pgid" 2>/dev/null || true
  sleep 0.3

  run --separate-stderr cog longrun finalize --state "$st"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | jq -e '.state == "lost" and .exit_source == "reconstructed"' >/dev/null
}

@test "cog longrun cancel reaps the whole process group" {
  local st="${RD}/c.longrun.json"
  cog longrun start --label c --state "$st" -- bash -c 'sleep 30' >/dev/null
  local pgid
  pgid="$(jq -r '.pgid' "$st")"

  run cog longrun cancel --state "$st"
  assert_success
  printf '%s\n' "$output" | jq -e '.state == "cancelled"' >/dev/null
  sleep 0.2
  run kill -0 -"$pgid"
  assert_failure
}

@test "cog longrun list enumerates jobs as a JSON array" {
  local st="${RD}/l.longrun.json"
  cog longrun start --label l --state "$st" -- bash -c 'exit 0' >/dev/null
  cog longrun finalize --state "$st" --max-wall 30 >/dev/null

  run cog longrun list --run-base "$RD"
  assert_success
  printf '%s\n' "$output" | jq -e 'type == "array" and (map(.label) | index("l") != null)' >/dev/null
}

@test "cog longrun status requires --state" {
  run --separate-stderr cog longrun status
  assert_failure
  [[ $stderr == *"missing --state"* ]]
}
