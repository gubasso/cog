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
  assert_output --partial 'Usage: cog gate approve --round-id <id> --round-path <file>'
}

@test "cog gate rejects an unknown verb" {
  run --separate-stderr cog gate frobnicate

  assert_failure
  [[ $stderr == *"unknown gate mode"* ]]
}

# --- operator-approval gate -----------------------------------------------

@test "cog gate approve then check-approval passes on an unchanged round" {
  local round="${BATS_TEST_TMPDIR}/round.md"
  printf 'round body\n' >"$round"

  run cog gate approve --round-id r1 --round-path "$round" --approver alice
  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and (.approval_path | type == "string")' >/dev/null

  run cog gate check-approval --round-id r1 --round-path "$round"
  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .status == "approved"' >/dev/null
}

@test "cog gate check-approval fails on a missing approval" {
  local round="${BATS_TEST_TMPDIR}/round.md"
  printf 'round body\n' >"$round"

  run cog gate check-approval --round-id never --round-path "$round"
  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and .status == "missing"' >/dev/null
}

@test "cog gate check-approval fails when the round changed after approval" {
  local round="${BATS_TEST_TMPDIR}/round.md"
  printf 'round body\n' >"$round"
  cog gate approve --round-id r2 --round-path "$round" >/dev/null
  printf 'tampered body\n' >"$round"

  run cog gate check-approval --round-id r2 --round-path "$round"
  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and .status == "hash-mismatch"' >/dev/null
}

@test "cog gate check-approval fails when the approval is stale" {
  local round="${BATS_TEST_TMPDIR}/round.md"
  printf 'round body\n' >"$round"
  cog gate approve --round-id r3 --round-path "$round" >/dev/null

  run cog gate check-approval --round-id r3 --round-path "$round" --ttl 0
  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and .status == "stale"' >/dev/null
}

@test "cog gate prune-approvals removes expired approvals" {
  local round="${BATS_TEST_TMPDIR}/round.md"
  printf 'round body\n' >"$round"
  cog gate approve --round-id r4 --round-path "$round" >/dev/null

  run cog gate prune-approvals --older-than 0
  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and (.pruned | length == 1)' >/dev/null

  run cog gate check-approval --round-id r4 --round-path "$round"
  assert_failure
  printf '%s\n' "$output" | jq -e '.status == "missing"' >/dev/null
}
