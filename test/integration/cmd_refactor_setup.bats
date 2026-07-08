setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_DATA_HOME="${BATS_TEST_TMPDIR}/data"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  unset RUN_DIR
  export REFACTOR_GUIDELINE="${BATS_TEST_TMPDIR}/guideline.md"
  mkdir -p "$HOME" "$XDG_DATA_HOME/cog/skill-refs/refactor" "$XDG_STATE_HOME" "${BATS_TEST_TMPDIR}/source" "${BATS_TEST_TMPDIR}/target"
  printf 'templates\n' >"${XDG_DATA_HOME}/cog/skill-refs/refactor/refactor-plan-templates.md"
  printf 'refusal\n' >"${XDG_DATA_HOME}/cog/skill-refs/refactor/refactor-refusal-list.md"
  printf 'madr\n' >"${XDG_DATA_HOME}/cog/skill-refs/refactor/madr-template.md"
  printf 'guideline\n' >"$REFACTOR_GUIDELINE"
}

@test "cog refactor-setup resolves setup paths" {
  run cog refactor-setup --source "${BATS_TEST_TMPDIR}/source" --target-root "${BATS_TEST_TMPDIR}/target" --target-lang bash --json

  assert_success
  printf '%s\n' "$output" | jq -e '
    .ok == true
    and .source_root == "'"${BATS_TEST_TMPDIR}"'/source"
    and .target_lang == "bash"
    and .guideline.source == "REFACTOR_GUIDELINE"
    and (.references.templates | endswith("refactor/refactor-plan-templates.md"))
  ' >/dev/null
}

@test "cog refactor-setup reports source target equality" {
  run cog refactor-setup --source "${BATS_TEST_TMPDIR}/source" --target-root "${BATS_TEST_TMPDIR}/source" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == false and .reason == "source and target must be different paths"' >/dev/null
}

@test "cog refactor-setup --help dispatches" {
  run cog refactor-setup --help

  assert_success
  [[ $output == *"Resolve refactor migration setup paths"* ]]
}
