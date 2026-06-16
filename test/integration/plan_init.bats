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
  printf '%s\n' "$output" | jq -e '.ok == true and (.created | length) == 4 and .legacy_plan_dir == false' >/dev/null
  [ -d "${repo}/.implementation-plans/plans" ]
  [ -f "${repo}/.implementation-plans/README.md" ]
  grep -F "plans: []" "${repo}/.implementation-plans/QUEUE.yaml"

  run cog plan-init --repo-root "$repo" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and (.existing | index("'"${repo}"'/.implementation-plans/QUEUE.yaml"))' >/dev/null
}

@test "cog plan-init writes an output fragment" {
  local repo="${BATS_TEST_TMPDIR}/repo"
  local out="${BATS_TEST_TMPDIR}/plan-init.json"
  mkdir -p "$repo"

  run cog plan-init --repo-root "$repo" "$out"

  assert_success
  assert_output "RESOLVED ${out}"
  jq -e '.queue_path | endswith(".implementation-plans/QUEUE.yaml")' "$out" >/dev/null
}

@test "cog plan-init --help dispatches" {
  run cog plan-init --help

  assert_success
  [[ $output == *"Bootstrap implementation plan root files"* ]]
}
