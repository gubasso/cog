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

@test "cog editorconfig-apply copies the editorconfig template" {
  run cog editorconfig-apply --project-root "${BATS_TEST_TMPDIR}/repo" --type rust --json

  assert_success
  [ -f "${BATS_TEST_TMPDIR}/repo/.editorconfig" ]
  grep -q '\[\*\.rs\]' "${BATS_TEST_TMPDIR}/repo/.editorconfig"
  printf '%s\n' "$output" | jq -e '.ok == true and ([.copied[].dst] | any(endswith("/.editorconfig")))' >/dev/null
}

@test "cog editorconfig-apply aborts on conflict" {
  touch "${BATS_TEST_TMPDIR}/repo/.editorconfig"

  run --separate-stderr cog editorconfig-apply --project-root "${BATS_TEST_TMPDIR}/repo" --type rust --json

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and .reason == "destination conflict"' >/dev/null
}

@test "cog editorconfig-apply skips an existing file under skip policy" {
  printf 'root = true\n' >"${BATS_TEST_TMPDIR}/repo/.editorconfig"

  run cog editorconfig-apply --project-root "${BATS_TEST_TMPDIR}/repo" --type rust --conflict skip --json

  assert_success
  printf '%s\n' "$output" | jq -e '[.skipped[].dst] | any(endswith("/.editorconfig"))' >/dev/null
  [ "$(cat "${BATS_TEST_TMPDIR}/repo/.editorconfig")" = "root = true" ]
}

@test "cog editorconfig-apply --help dispatches" {
  run cog editorconfig-apply --help

  assert_success
  [[ $output == *"Apply an editorconfig template"* ]]
}
