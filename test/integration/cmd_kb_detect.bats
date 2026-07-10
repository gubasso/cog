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

@test "cog kb-detect resolves markdown for a knowledge-base project" {
  mkdir -p "${BATS_TEST_TMPDIR}/repo/tech"
  printf '# a\n' >"${BATS_TEST_TMPDIR}/repo/README.md"
  printf '# b\n' >"${BATS_TEST_TMPDIR}/repo/tech/b.md"
  printf '# c\n' >"${BATS_TEST_TMPDIR}/repo/tech/c.md"

  run cog kb-detect --project-root "${BATS_TEST_TMPDIR}/repo" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .detected_type == "markdown" and (.template_root | endswith("/templates/knowledge-base"))' >/dev/null
}

@test "cog kb-detect fails on a non-knowledge-base project" {
  touch "${BATS_TEST_TMPDIR}/repo/Cargo.toml"

  run --separate-stderr cog kb-detect --project-root "${BATS_TEST_TMPDIR}/repo" --json

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false' >/dev/null
}

@test "cog kb-detect --help dispatches" {
  run cog kb-detect --help

  assert_success
  [[ $output == *"Detect knowledge-base scaffold type"* ]]
}
