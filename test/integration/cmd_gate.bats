setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
}

# --- dispatch -------------------------------------------------------------

@test "cog gate without a verb shows usage" {
  run cog gate

  assert_success
  assert_output --partial 'Usage: cog gate approve --gate-id <id> --artifact <file>'
}

@test "cog gate rejects an unknown verb" {
  run --separate-stderr cog gate frobnicate

  assert_failure
  [[ $stderr == *"unknown gate mode"* ]]
}

@test "cog gate rejects the retired round flags" {
  local artifact="${BATS_TEST_TMPDIR}/work.md"
  printf 'work body\n' >"$artifact"

  run --separate-stderr cog gate approve --round-id r0 --round-path "$artifact"
  assert_failure
  [[ $stderr == *"unknown gate approve option"* ]]

  run --separate-stderr cog gate check-approval --round-id r0 --round-path "$artifact"
  assert_failure
  [[ $stderr == *"unknown gate check-approval option"* ]]
}

# --- operator-approval gate -----------------------------------------------

@test "cog gate approve binds the record to the artifact under approval" {
  local artifact="${BATS_TEST_TMPDIR}/work.md"
  printf 'work body\n' >"$artifact"

  run cog gate approve --gate-id r1 --artifact "$artifact" --approver alice
  assert_success
  printf '%s\n' "$output" | jq -e --arg artifact "$artifact" \
    '.ok == true
      and (.approval_path | type == "string")
      and .record.schema == "cog.gate.approval.v2"
      and .record.gate_id == "r1"
      and .record.artifact_path == $artifact
      and (.record.content_hash | length == 64)' >/dev/null
}

@test "cog gate approve then check-approval passes on an unchanged artifact" {
  local artifact="${BATS_TEST_TMPDIR}/work.md"
  printf 'work body\n' >"$artifact"

  cog gate approve --gate-id r1 --artifact "$artifact" --approver alice >/dev/null

  run cog gate check-approval --gate-id r1 --artifact "$artifact"
  assert_success
  printf '%s\n' "$output" | jq -e --arg artifact "$artifact" \
    '.schema == "cog.gate.approval-check.v2"
      and .ok == true
      and .status == "approved"
      and .gate_id == "r1"
      and .artifact_path == $artifact' >/dev/null
}

@test "cog gate check-approval fails on a missing approval" {
  local artifact="${BATS_TEST_TMPDIR}/work.md"
  printf 'work body\n' >"$artifact"

  run cog gate check-approval --gate-id never --artifact "$artifact"
  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and .status == "missing"' >/dev/null
}

@test "cog gate check-approval fails when the artifact changed after approval" {
  local artifact="${BATS_TEST_TMPDIR}/work.md"
  printf 'work body\n' >"$artifact"
  cog gate approve --gate-id r2 --artifact "$artifact" >/dev/null
  printf 'tampered body\n' >"$artifact"

  run cog gate check-approval --gate-id r2 --artifact "$artifact"
  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and .status == "hash-mismatch"' >/dev/null
}

@test "cog gate check-approval fails when the approval is stale" {
  local artifact="${BATS_TEST_TMPDIR}/work.md"
  printf 'work body\n' >"$artifact"
  cog gate approve --gate-id r3 --artifact "$artifact" >/dev/null

  run cog gate check-approval --gate-id r3 --artifact "$artifact" --ttl 0
  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and .status == "stale"' >/dev/null
}

@test "cog gate check-approval fails closed on a missing artifact" {
  run --separate-stderr cog gate check-approval --gate-id r5 --artifact "${BATS_TEST_TMPDIR}/absent.md"

  assert_failure
  [[ $stderr == *"artifact not found"* ]]
}

@test "cog gate prune-approvals removes expired approvals" {
  local artifact="${BATS_TEST_TMPDIR}/work.md"
  printf 'work body\n' >"$artifact"
  cog gate approve --gate-id r4 --artifact "$artifact" >/dev/null

  run cog gate prune-approvals --older-than 0
  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and (.pruned | length == 1)' >/dev/null

  run cog gate check-approval --gate-id r4 --artifact "$artifact"
  assert_failure
  printf '%s\n' "$output" | jq -e '.status == "missing"' >/dev/null
}
