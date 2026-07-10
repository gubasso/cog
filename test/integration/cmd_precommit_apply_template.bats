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

@test "cog precommit-apply-template copies template and committed config" {
  run cog precommit-apply-template --project-root "${BATS_TEST_TMPDIR}/repo" --type rust --json

  assert_success
  [ -f "${BATS_TEST_TMPDIR}/repo/.pre-commit-config.yaml" ]
  [ -f "${BATS_TEST_TMPDIR}/repo/committed.toml" ]
  printf '%s\n' "$output" | jq -e '.ok == true and (.copied | length >= 2)' >/dev/null
}

@test "cog precommit-apply-template aborts on config conflict" {
  touch "${BATS_TEST_TMPDIR}/repo/.pre-commit-config.yaml"

  run --separate-stderr cog precommit-apply-template --project-root "${BATS_TEST_TMPDIR}/repo" --type rust --json

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and .reason == "destination conflict"' >/dev/null
}

@test "cog precommit-apply-template markdown defaults to typos and appends its hook" {
  run cog precommit-apply-template --project-root "${BATS_TEST_TMPDIR}/repo" --type markdown --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .spell == "typos" and .spell_hook_appended == true' >/dev/null
  [ -f "${BATS_TEST_TMPDIR}/repo/_typos.toml" ]
  [ ! -f "${BATS_TEST_TMPDIR}/repo/cspell.config.yaml" ]
  grep -q 'crate-ci/typos' "${BATS_TEST_TMPDIR}/repo/.pre-commit-config.yaml"
}

@test "cog precommit-apply-template markdown --spell cspell copies cspell companions and hook" {
  run cog precommit-apply-template --project-root "${BATS_TEST_TMPDIR}/repo" --type markdown --spell cspell --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .spell == "cspell" and .spell_hook_appended == true' >/dev/null
  [ -f "${BATS_TEST_TMPDIR}/repo/cspell.config.yaml" ]
  [ -f "${BATS_TEST_TMPDIR}/repo/project-words.txt" ]
  [ ! -f "${BATS_TEST_TMPDIR}/repo/_typos.toml" ]
  grep -q 'streetsidesoftware/cspell-cli' "${BATS_TEST_TMPDIR}/repo/.pre-commit-config.yaml"
  run ! grep -q 'crate-ci/typos' "${BATS_TEST_TMPDIR}/repo/.pre-commit-config.yaml"
}

@test "cog precommit-apply-template rejects invalid --spell value" {
  run --separate-stderr cog precommit-apply-template --project-root "${BATS_TEST_TMPDIR}/repo" --type markdown --spell aspell --json

  assert_failure
  [[ $stderr == *"InvalidInput"* ]]
}

@test "cog precommit-apply-template does not overlay spell files onto code templates" {
  run cog precommit-apply-template --project-root "${BATS_TEST_TMPDIR}/repo" --type rust --json

  assert_success
  printf '%s\n' "$output" | jq -e '.spell_hook_appended == false' >/dev/null
  [ ! -f "${BATS_TEST_TMPDIR}/repo/cspell.config.yaml" ]
  [ ! -f "${BATS_TEST_TMPDIR}/repo/project-words.txt" ]
}

@test "cog precommit-apply-template --help dispatches" {
  run cog precommit-apply-template --help

  assert_success
  [[ $output == *"Apply a pre-commit template"* ]]
}
