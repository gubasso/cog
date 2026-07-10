setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_DATA_HOME="${BATS_TEST_TMPDIR}/data"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  unset RUN_DIR REFACTOR_GUIDELINE
  mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"
}

@test "cog precommit-spell-select maps English-only to typos" {
  run cog precommit-spell-select --languages en --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .spell == "typos" and .non_english == false' >/dev/null
}

@test "cog precommit-spell-select maps a non-English language to cspell" {
  run cog precommit-spell-select --languages "en,pt_BR" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .spell == "cspell" and .non_english == true and (.languages | index("pt_BR") != null)' >/dev/null
}

@test "cog precommit-spell-select defaults an empty language set to typos" {
  run cog precommit-spell-select --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .spell == "typos" and (.languages | length) == 0' >/dev/null
}

@test "cog precommit-spell-select rejects a malformed language token" {
  run --separate-stderr cog precommit-spell-select --languages english --json

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and (.reason | test("invalid language token"))' >/dev/null
}

@test "cog precommit-spell-select --help dispatches" {
  run cog precommit-spell-select --help

  assert_success
  [[ $output == *"spell checker"* ]]
}
