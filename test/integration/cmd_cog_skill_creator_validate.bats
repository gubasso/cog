setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_DATA_HOME="${BATS_TEST_TMPDIR}/data"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  export RUN_DIR="${BATS_TEST_TMPDIR}/run"
  unset REFACTOR_GUIDELINE
  mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$RUN_DIR" "${BATS_TEST_TMPDIR}/repo/skills/claude/demo-skill"
}

@test "cog cog-skill-creator-validate reports cog skill collisions only" {
  run --separate-stderr cog cog-skill-creator-validate --name demo-skill --scope project --project-root "${BATS_TEST_TMPDIR}/repo" --json

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and (.collisions[0] | contains("/skills/claude/demo-skill"))' >/dev/null
  [[ $output != *".dotfiles"* ]]
  [[ $output != *".claude/skills"* ]]
}

@test "cog cog-skill-creator-validate detects personal codex skill collisions" {
  export COG_SKILLS_HOME="${BATS_TEST_TMPDIR}/skillshome"
  mkdir -p "${COG_SKILLS_HOME}/codex/demo-skill"

  run --separate-stderr cog cog-skill-creator-validate --name demo-skill --scope personal --run-dir "$RUN_DIR" --json

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and (.collisions[] | contains("/codex/demo-skill"))' >/dev/null
}

@test "cog cog-skill-creator-validate rejects reserved names in build mode" {
  run --separate-stderr cog cog-skill-creator-validate --name claude --scope project --project-root "${BATS_TEST_TMPDIR}/repo" --json
  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and .valid_name == false' >/dev/null

  run --separate-stderr cog cog-skill-creator-validate --name anthropic --scope project --project-root "${BATS_TEST_TMPDIR}/repo" --json
  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and .valid_name == false' >/dev/null
}

@test "cog cog-skill-creator-validate validates draft files" {
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

  run cog cog-skill-creator-validate --draft "${BATS_TEST_TMPDIR}/SKILL.md" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .mode == "draft"' >/dev/null
}

@test "cog cog-skill-creator-validate --help dispatches" {
  run cog cog-skill-creator-validate --help

  assert_success
  [[ $output == *"Validate cog-skill-creator inputs"* ]]
}
