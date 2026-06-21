setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  mkdir -p "$HOME" "$XDG_STATE_HOME"
}

@test "cog plan-init creates implementation plan root and is idempotent" {
  local repo="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "$repo"

  run cog plan-init --repo-root "$repo" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and (.created | length) == 4' >/dev/null
  [ -d "${repo}/.implementation-plans/plans" ]
  [ -f "${repo}/.implementation-plans/README.md" ]
  grep -F "plans: []" "${repo}/.implementation-plans/queue-plans.yaml"

  run cog plan-init --repo-root "$repo" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and (.existing | index("'"${repo}"'/.implementation-plans/queue-plans.yaml"))' >/dev/null
}

@test "cog plan-init writes an output fragment" {
  local repo="${BATS_TEST_TMPDIR}/repo"
  local out="${BATS_TEST_TMPDIR}/plan-init.json"
  mkdir -p "$repo"

  run cog plan-init --repo-root "$repo" "$out"

  assert_success
  assert_output "RESOLVED ${out}"
  jq -e '.queue_path | endswith(".implementation-plans/queue-plans.yaml")' "$out" >/dev/null
}

@test "cog plan-init fails closed on a nested plan directory" {
  local repo="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "${repo}/.implementation-plans/plans/parent/child"
  printf 'rounds: []\n' >"${repo}/.implementation-plans/plans/parent/child/queue-rounds.yaml"

  run cog plan-init --repo-root "$repo" --json

  assert_failure
  assert_output --partial "nested plan directory detected"
  assert_output --partial "plans/parent/child/queue-rounds.yaml"
}

@test "cog plan-init succeeds for flat sibling plans" {
  local repo="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "${repo}/.implementation-plans/plans/flat-a" "${repo}/.implementation-plans/plans/flat-b"
  printf 'rounds: []\n' >"${repo}/.implementation-plans/plans/flat-a/queue-rounds.yaml"
  printf 'rounds: []\n' >"${repo}/.implementation-plans/plans/flat-b/queue-rounds.yaml"

  run cog plan-init --repo-root "$repo" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true' >/dev/null
}

@test "cog plan-init --help dispatches" {
  run cog plan-init --help

  assert_success
  [[ $output == *"Bootstrap implementation plan root files"* ]]
}
