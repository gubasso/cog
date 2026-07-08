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

@test "cog readme-apply copies the README skeleton" {
  run cog readme-apply --project-root "${BATS_TEST_TMPDIR}/repo" --json

  assert_success
  [ -f "${BATS_TEST_TMPDIR}/repo/README.md" ]
  printf '%s\n' "$output" | jq -e '.ok == true and ([.copied[].dst] | any(endswith("/README.md")))' >/dev/null
}

@test "cog readme-apply aborts on conflict" {
  touch "${BATS_TEST_TMPDIR}/repo/README.md"

  run --separate-stderr cog readme-apply --project-root "${BATS_TEST_TMPDIR}/repo" --json

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and .reason == "destination conflict"' >/dev/null
}

@test "cog readme-apply skips an existing file under skip policy" {
  printf '# Existing\n' >"${BATS_TEST_TMPDIR}/repo/README.md"

  run cog readme-apply --project-root "${BATS_TEST_TMPDIR}/repo" --conflict skip --json

  assert_success
  printf '%s\n' "$output" | jq -e '[.skipped[].dst] | any(endswith("/README.md"))' >/dev/null
  [ "$(cat "${BATS_TEST_TMPDIR}/repo/README.md")" = "# Existing" ]
}

@test "cog readme-apply --help dispatches" {
  run cog readme-apply --help

  assert_success
  [[ $output == *"Apply a README skeleton"* ]]
}
