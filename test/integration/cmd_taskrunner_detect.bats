setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_DATA_HOME="${BATS_TEST_TMPDIR}/data"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  unset RUN_DIR
  mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "${BATS_TEST_TMPDIR}/repo"
}

@test "cog taskrunner-detect reports just for a bare project" {
  run cog taskrunner-detect --project-root "${BATS_TEST_TMPDIR}/repo" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .type == "just"' >/dev/null
}

@test "cog taskrunner-detect still reports just when a foreign Makefile exists" {
  touch "${BATS_TEST_TMPDIR}/repo/Makefile"

  run cog taskrunner-detect --project-root "${BATS_TEST_TMPDIR}/repo" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .type == "just" and (.signals | length) == 0' >/dev/null
}

@test "cog taskrunner-detect surfaces build-tool signals" {
  touch "${BATS_TEST_TMPDIR}/repo/Cargo.toml"

  run cog taskrunner-detect --project-root "${BATS_TEST_TMPDIR}/repo" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.type == "just" and (.signals | index("cargo (Cargo.toml)"))' >/dev/null
}

@test "cog taskrunner-detect --help dispatches" {
  run cog taskrunner-detect --help

  assert_success
  [[ $output == *"Detect task-runner build signals"* ]]
}
