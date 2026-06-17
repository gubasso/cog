setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_DATA_HOME="${BATS_TEST_TMPDIR}/data"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  export RUN_DIR="${BATS_TEST_TMPDIR}/run"
  unset DOCS_NOTES_REPO REFACTOR_GUIDELINE RIPTASK_REPO
  mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$RUN_DIR" "${BATS_TEST_TMPDIR}/repo/skills/claude/demo-skill"
}

@test "cog skill-builder-validate reports cog skill collisions only" {
  run --separate-stderr cog skill-builder-validate --name demo-skill --scope project --project-root "${BATS_TEST_TMPDIR}/repo" --json

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and (.collisions[0] | contains("/skills/claude/demo-skill"))' >/dev/null
  [[ $output != *".dotfiles"* ]]
  [[ $output != *".claude/skills"* ]]
}

@test "cog skill-builder-validate validates draft files" {
  cat >"${BATS_TEST_TMPDIR}/SKILL.md" <<'EOF'
---
name: demo-skill
description: Demo.
---

<!-- trigger-tests: "demo" -->

```text
ok
```
EOF

  run cog skill-builder-validate --draft "${BATS_TEST_TMPDIR}/SKILL.md" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .mode == "draft"' >/dev/null
}

@test "cog skill-builder-validate --help dispatches" {
  run cog skill-builder-validate --help

  assert_success
  [[ $output == *"Validate skill-builder inputs"* ]]
}
