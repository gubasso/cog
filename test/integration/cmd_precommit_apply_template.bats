setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_DATA_HOME="${BATS_TEST_TMPDIR}/data"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  unset RUN_DIR REFACTOR_GUIDELINE
  mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "${BATS_TEST_TMPDIR}/repo"
}

@test "cog precommit-apply-template copies template and committed config" {
  run cog precommit-apply-template --project-root "${BATS_TEST_TMPDIR}/repo" --type rust --json

  assert_success
  [ -f "${BATS_TEST_TMPDIR}/repo/.pre-commit-config.yaml" ]
  [ -f "${BATS_TEST_TMPDIR}/repo/committed.toml" ]
  printf '%s\n' "$output" | jq -e '.ok == true and (.copied | length >= 2)' >/dev/null
}

@test "cog precommit-apply-template aborts on config conflict" {
  touch "${BATS_TEST_TMPDIR}/repo/.pre-commit-config.yaml"

  run --separate-stderr cog precommit-apply-template --project-root "${BATS_TEST_TMPDIR}/repo" --type rust --json

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and .reason == "destination conflict"' >/dev/null
}

@test "cog precommit-apply-template --help dispatches" {
  run cog precommit-apply-template --help

  assert_success
  [[ $output == *"Apply a pre-commit template"* ]]
}
