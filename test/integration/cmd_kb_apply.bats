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

@test "cog kb-apply scaffolds the docs specs tree" {
  run cog kb-apply --project-root "${BATS_TEST_TMPDIR}/repo" --template-root "${BATS_TEST_DIRNAME}/../../skill-refs/templates/knowledge-base" --type markdown --json

  assert_success
  [ -f "${BATS_TEST_TMPDIR}/repo/_docs/README.md" ]
  [ -f "${BATS_TEST_TMPDIR}/repo/_docs/explanation/knowledge-base-architecture.md" ]
  [ -f "${BATS_TEST_TMPDIR}/repo/_docs/reference/agents-digest-template.md" ]
  [ ! -e "${BATS_TEST_TMPDIR}/repo/docs/README.md" ]
  printf '%s\n' "$output" | jq -e '.ok == true and (.copied | length >= 5)' >/dev/null
}

@test "cog kb-apply aborts on conflict" {
  mkdir -p "${BATS_TEST_TMPDIR}/repo/_docs"
  touch "${BATS_TEST_TMPDIR}/repo/_docs/README.md"

  run --separate-stderr cog kb-apply --project-root "${BATS_TEST_TMPDIR}/repo" --template-root "${BATS_TEST_DIRNAME}/../../skill-refs/templates/knowledge-base" --type markdown --json

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and .reason == "destination conflict"' >/dev/null
}

@test "cog kb-apply skips existing files under skip policy" {
  mkdir -p "${BATS_TEST_TMPDIR}/repo/_docs"
  printf 'keep\n' >"${BATS_TEST_TMPDIR}/repo/_docs/README.md"

  run cog kb-apply --project-root "${BATS_TEST_TMPDIR}/repo" --template-root "${BATS_TEST_DIRNAME}/../../skill-refs/templates/knowledge-base" --type markdown --conflict skip --json

  assert_success
  assert_equal "keep" "$(cat "${BATS_TEST_TMPDIR}/repo/_docs/README.md")"
  printf '%s\n' "$output" | jq -e '.ok == true and (.skipped | length >= 1)' >/dev/null
}

@test "cog kb-apply --help dispatches" {
  run cog kb-apply --help

  assert_success
  [[ $output == *"Apply a knowledge-base scaffold"* ]]
}
