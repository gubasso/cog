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
  run cog taskrunner-apply --project-root "${BATS_TEST_TMPDIR}/repo" --json

  assert_success
  [ -f "${BATS_TEST_TMPDIR}/repo/justfile" ]
  grep -q '^lint:' "${BATS_TEST_TMPDIR}/repo/justfile"
  printf '%s\n' "$output" | jq -e '.ok == true and .type == "just" and ([.copied[].dst] | any(endswith("/justfile")))' >/dev/null
}

@test "cog taskrunner-apply aborts on an existing justfile" {
  printf 'existing:\n    @true\n' >"${BATS_TEST_TMPDIR}/repo/justfile"

  run --separate-stderr cog taskrunner-apply --project-root "${BATS_TEST_TMPDIR}/repo" --json

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and .reason == "destination conflict"' >/dev/null
}

@test "cog taskrunner-apply skips an existing justfile under skip policy" {
  printf 'existing:\n    @true\n' >"${BATS_TEST_TMPDIR}/repo/justfile"

  run cog taskrunner-apply --project-root "${BATS_TEST_TMPDIR}/repo" --conflict skip --json

  assert_success
  printf '%s\n' "$output" | jq -e '[.skipped[].dst] | any(endswith("/justfile"))' >/dev/null
  grep -q '^existing:' "${BATS_TEST_TMPDIR}/repo/justfile"
}

@test "cog taskrunner-apply rejects an unknown conflict policy" {
  run --separate-stderr cog taskrunner-apply --project-root "${BATS_TEST_TMPDIR}/repo" --conflict clobber --json

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and .reason == "conflict policy must be overwrite, skip, or abort"' >/dev/null
}

@test "cog taskrunner-apply ignores a foreign Makefile and still deploys a justfile" {
  printf 'existing:\n\t@true\n' >"${BATS_TEST_TMPDIR}/repo/Makefile"

  run cog taskrunner-apply --project-root "${BATS_TEST_TMPDIR}/repo" --json

  assert_success
  [ -f "${BATS_TEST_TMPDIR}/repo/justfile" ]
  printf '%s\n' "$output" | jq -e '.ok == true and ([.copied[].dst] | any(endswith("/justfile")))' >/dev/null
}

@test "cog taskrunner-apply --append injects only the missing recipes, preserving existing ones" {
  printf 'build:\n    @echo my-build\n' >"${BATS_TEST_TMPDIR}/repo/justfile"

  run cog taskrunner-apply --project-root "${BATS_TEST_TMPDIR}/repo" --append --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .mode == "append" and (.appended | index("check")) and (.appended | index("build") | not)' >/dev/null
  grep -q '@echo my-build' "${BATS_TEST_TMPDIR}/repo/justfile"
  grep -qE '^lint:' "${BATS_TEST_TMPDIR}/repo/justfile"
  grep -qE '^check: fmt lint test' "${BATS_TEST_TMPDIR}/repo/justfile"
}

@test "cog taskrunner-apply --append is idempotent" {
  printf 'build:\n    @echo my-build\n' >"${BATS_TEST_TMPDIR}/repo/justfile"
  cog taskrunner-apply --project-root "${BATS_TEST_TMPDIR}/repo" --append --json >/dev/null

  run cog taskrunner-apply --project-root "${BATS_TEST_TMPDIR}/repo" --append --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and (.appended | length) == 0' >/dev/null
}

@test "cog taskrunner-apply --append copies a fresh file when none exists" {
  run cog taskrunner-apply --project-root "${BATS_TEST_TMPDIR}/repo" --append --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and ([.copied[].dst] | any(endswith("/justfile")))' >/dev/null
  grep -qE '^lint:' "${BATS_TEST_TMPDIR}/repo/justfile"
}

@test "cog taskrunner-apply --append augments a dot-prefixed justfile in place" {
  printf 'build:\n    @echo my-build\n' >"${BATS_TEST_TMPDIR}/repo/.justfile"

  run cog taskrunner-apply --project-root "${BATS_TEST_TMPDIR}/repo" --append --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and (.appended | index("lint"))' >/dev/null
  [ ! -e "${BATS_TEST_TMPDIR}/repo/justfile" ]
  grep -q '@echo my-build' "${BATS_TEST_TMPDIR}/repo/.justfile"
  grep -qE '^lint:' "${BATS_TEST_TMPDIR}/repo/.justfile"
}

@test "cog taskrunner-apply aborts on an existing dot-prefixed justfile" {
  printf 'existing:\n    @true\n' >"${BATS_TEST_TMPDIR}/repo/.justfile"

  run --separate-stderr cog taskrunner-apply --project-root "${BATS_TEST_TMPDIR}/repo" --json

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and .reason == "destination conflict"' >/dev/null
  [ ! -e "${BATS_TEST_TMPDIR}/repo/justfile" ]
}

@test "cog taskrunner-apply --help dispatches" {
  run cog taskrunner-apply --help

  assert_success
  [[ $output == *"Apply the justfile task-runner template"* ]]
}
