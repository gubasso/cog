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

@test "cog taskrunner-apply writes a justfile" {
  run cog taskrunner-apply --project-root "${BATS_TEST_TMPDIR}/repo" --type just --json

  assert_success
  [ -f "${BATS_TEST_TMPDIR}/repo/justfile" ]
  grep -q '^lint:' "${BATS_TEST_TMPDIR}/repo/justfile"
  printf '%s\n' "$output" | jq -e '.ok == true and ([.copied[].dst] | any(endswith("/justfile")))' >/dev/null
}

@test "cog taskrunner-apply writes a Makefile" {
  run cog taskrunner-apply --project-root "${BATS_TEST_TMPDIR}/repo" --type make --json

  assert_success
  [ -f "${BATS_TEST_TMPDIR}/repo/Makefile" ]
  grep -q '^.PHONY:' "${BATS_TEST_TMPDIR}/repo/Makefile"
  printf '%s\n' "$output" | jq -e '.ok == true and ([.copied[].dst] | any(endswith("/Makefile")))' >/dev/null
}

@test "cog taskrunner-apply aborts on an existing Makefile" {
  printf 'existing:\n\t@true\n' >"${BATS_TEST_TMPDIR}/repo/Makefile"

  run --separate-stderr cog taskrunner-apply --project-root "${BATS_TEST_TMPDIR}/repo" --type make --json

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and .reason == "destination conflict"' >/dev/null
}

@test "cog taskrunner-apply skips an existing Makefile under skip policy" {
  printf 'existing:\n\t@true\n' >"${BATS_TEST_TMPDIR}/repo/Makefile"

  run cog taskrunner-apply --project-root "${BATS_TEST_TMPDIR}/repo" --type make --conflict skip --json

  assert_success
  printf '%s\n' "$output" | jq -e '[.skipped[].dst] | any(endswith("/Makefile"))' >/dev/null
  grep -q '^existing:' "${BATS_TEST_TMPDIR}/repo/Makefile"
}

@test "cog taskrunner-apply rejects an unknown type" {
  run --separate-stderr cog taskrunner-apply --project-root "${BATS_TEST_TMPDIR}/repo" --type cmake --json

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and .reason == "type must be just or make"' >/dev/null
}

@test "cog taskrunner-apply --help dispatches" {
  run cog taskrunner-apply --help

  assert_success
  [[ $output == *"Apply a task-runner template"* ]]
}
