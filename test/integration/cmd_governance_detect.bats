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

@test "cog governance-detect reports absent docs on an empty project" {
  run cog governance-detect --project-root "${BATS_TEST_TMPDIR}/repo" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .present == false and .detected_type == "generic" and (.artifacts | length) == 3' >/dev/null
}

@test "cog governance-detect reports present when both docs exist" {
  touch "${BATS_TEST_TMPDIR}/repo/CLAUDE.md" "${BATS_TEST_TMPDIR}/repo/AGENTS.md"

  run cog governance-detect --project-root "${BATS_TEST_TMPDIR}/repo" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.present == true' >/dev/null
}

@test "cog governance-detect stays absent when only one doc exists" {
  touch "${BATS_TEST_TMPDIR}/repo/CLAUDE.md"

  run cog governance-detect --project-root "${BATS_TEST_TMPDIR}/repo" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.present == false' >/dev/null
}

@test "cog governance-detect fails on a bad project root" {
  run --separate-stderr cog governance-detect --project-root "${BATS_TEST_TMPDIR}/nope" --json

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and .reason == "project root is not a directory"' >/dev/null
}

@test "cog governance-detect --help dispatches" {
  run cog governance-detect --help

  assert_success
  [[ $output == *"Detect project governance docs"* ]]
}
