setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_DATA_HOME="${BATS_TEST_TMPDIR}/data"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  unset RUN_DIR DOCS_NOTES_REPO REFACTOR_GUIDELINE RIPTASK_REPO
  mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "${BATS_TEST_TMPDIR}/repo"
}

@test "cog taskrunner-detect defaults to just with no Makefile" {
  run cog taskrunner-detect --project-root "${BATS_TEST_TMPDIR}/repo" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .type == "just"' >/dev/null
}

@test "cog taskrunner-detect returns make when a Makefile exists" {
  touch "${BATS_TEST_TMPDIR}/repo/Makefile"

  run cog taskrunner-detect --project-root "${BATS_TEST_TMPDIR}/repo" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .type == "make" and (.signals | index("existing Makefile"))' >/dev/null
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
  [[ $output == *"Detect the task-runner type"* ]]
}
