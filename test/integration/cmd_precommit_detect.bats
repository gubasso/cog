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

@test "cog precommit-detect uses bundled default template root" {
  touch "${BATS_TEST_TMPDIR}/repo/Cargo.toml"

  run cog precommit-detect --project-root "${BATS_TEST_TMPDIR}/repo" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .detected_type == "rust" and (.template_root | endswith("/templates/pre-commit"))' >/dev/null
}

@test "cog precommit-detect reports conflicts" {
  touch "${BATS_TEST_TMPDIR}/repo/Cargo.toml" "${BATS_TEST_TMPDIR}/repo/package.json"

  run --separate-stderr cog precommit-detect --project-root "${BATS_TEST_TMPDIR}/repo" --json

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and (.conflicts | index("rust")) and (.conflicts | index("node"))' >/dev/null
}

@test "cog precommit-detect --help dispatches" {
  run cog precommit-detect --help

  assert_success
  [[ $output == *"Detect pre-commit template type"* ]]
}
