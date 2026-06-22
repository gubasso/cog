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

@test "cog editorconfig-detect uses bundled default template root" {
  touch "${BATS_TEST_TMPDIR}/repo/Cargo.toml"

  run cog editorconfig-detect --project-root "${BATS_TEST_TMPDIR}/repo" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .detected_type == "rust" and (.template_root | endswith("/templates/editorconfig"))' >/dev/null
}

@test "cog editorconfig-detect reports conflicts" {
  touch "${BATS_TEST_TMPDIR}/repo/Cargo.toml" "${BATS_TEST_TMPDIR}/repo/package.json"

  run --separate-stderr cog editorconfig-detect --project-root "${BATS_TEST_TMPDIR}/repo" --json

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and (.conflicts | index("rust")) and (.conflicts | index("node"))' >/dev/null
}

@test "cog editorconfig-detect --help dispatches" {
  run cog editorconfig-detect --help

  assert_success
  [[ $output == *"Detect editorconfig template type"* ]]
}
