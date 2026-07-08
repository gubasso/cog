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

@test "cog taskrunner-apply --append injects only the missing targets, preserving existing ones" {
  printf '.PHONY: build\n\nbuild:\n\t@echo my-build\n' >"${BATS_TEST_TMPDIR}/repo/Makefile"

  run cog taskrunner-apply --project-root "${BATS_TEST_TMPDIR}/repo" --type make --append --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .mode == "append" and (.appended | index("check")) and (.appended | index("build") | not)' >/dev/null
  grep -q '@echo my-build' "${BATS_TEST_TMPDIR}/repo/Makefile"
  grep -qE '^lint:' "${BATS_TEST_TMPDIR}/repo/Makefile"
  grep -qE '^check: fmt lint test' "${BATS_TEST_TMPDIR}/repo/Makefile"
  grep -qE '^\.PHONY: lint test fmt check' "${BATS_TEST_TMPDIR}/repo/Makefile"
}

@test "cog taskrunner-apply --append is idempotent" {
  printf '.PHONY: build\n\nbuild:\n\t@echo my-build\n' >"${BATS_TEST_TMPDIR}/repo/Makefile"
  cog taskrunner-apply --project-root "${BATS_TEST_TMPDIR}/repo" --type make --append --json >/dev/null

  run cog taskrunner-apply --project-root "${BATS_TEST_TMPDIR}/repo" --type make --append --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and (.appended | length) == 0' >/dev/null
}

@test "cog taskrunner-apply --append copies a fresh file when none exists" {
  run cog taskrunner-apply --project-root "${BATS_TEST_TMPDIR}/repo" --type make --append --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and ([.copied[].dst] | any(endswith("/Makefile")))' >/dev/null
  grep -qE '^\.PHONY:' "${BATS_TEST_TMPDIR}/repo/Makefile"
}

@test "cog taskrunner-apply --help dispatches" {
  run cog taskrunner-apply --help

  assert_success
  [[ $output == *"Apply a task-runner template"* ]]
}
