setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_DATA_HOME="${BATS_TEST_TMPDIR}/data"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  export RUN_DIR="${BATS_TEST_TMPDIR}/run"
  unset DOCS_NOTES_REPO REFACTOR_GUIDELINE RIPTASK_REPO
  mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$RUN_DIR" "${BATS_TEST_TMPDIR}/repo/skills/claude" "${BATS_TEST_TMPDIR}/repo/skills/codex"
}

@test "cog cog-skill-creator-scaffold emits codex project paths" {
  run cog cog-skill-creator-scaffold --name demo-skill --runtime codex --scope project --project-root "${BATS_TEST_TMPDIR}/repo" --companion references/guide.md --json

  assert_success
  printf '%s\n' "$output" | jq -e '.runtime == "codex" and .dest_dir == "'"${BATS_TEST_TMPDIR}"'/repo/skills/codex/demo-skill" and (.files | length == 2)' >/dev/null
  [[ $output != *".dotfiles"* ]]
  [[ $output != *".claude"* ]]
  [[ $output != *"/workspaces/.dotfiles"* ]]
}

@test "cog cog-skill-creator-scaffold rejects unsafe companions" {
  run --separate-stderr cog cog-skill-creator-scaffold --name demo-skill --companion ../bad --json

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and .reason == "unsafe companion path"' >/dev/null
}

@test "cog cog-skill-creator-scaffold --help dispatches" {
  run cog cog-skill-creator-scaffold --help

  assert_success
  [[ $output == *"Compute skill scaffold paths"* ]]
}
