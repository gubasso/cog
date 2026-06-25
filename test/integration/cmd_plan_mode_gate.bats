setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
}

@test "cog plan-mode-gate render emits the canonical standard stanza" {
  run cog plan-mode-gate render --skill demo

  assert_success
  # shellcheck disable=SC2016
  expected='<!-- cog-plan-mode-gate -->

**Phase 0 — Plan-mode gate.** If Claude Code **plan mode** is active (a system-reminder says plan
mode is on / that you must not make edits), **STOP** before any other work — parsing args,
researching, interviewing, delegating, or writing. Tell the user in one line to exit plan mode
(`Shift+Tab`) and re-invoke `/demo`. Do not call `ExitPlanMode`, and do not silently continue.'
  assert_output "$expected"
}

@test "cog plan-mode-gate render rejects the removed --orchestrator-noop flag" {
  run --separate-stderr cog plan-mode-gate render --skill demo --orchestrator-noop

  assert_failure
  [[ $stderr == *"unknown plan-mode-gate render option"* ]]
}

@test "cog plan-mode-gate render substitutes the skill name into the re-invoke instruction" {
  run cog plan-mode-gate render --skill review-plan-oneshot

  assert_success
  # shellcheck disable=SC2016
  assert_output --partial 're-invoke `/review-plan-oneshot`'
}

@test "cog plan-mode-gate render fails without --skill" {
  run --separate-stderr cog plan-mode-gate render

  assert_failure
  [[ $stderr == *"skill name"* ]]
}

@test "cog plan-mode-gate render rejects an invalid skill name" {
  run --separate-stderr cog plan-mode-gate render --skill "Bad Name"

  assert_failure
  [[ $stderr == *"invalid skill name"* ]]
}

@test "cog plan-mode-gate render rejects an unknown option" {
  run --separate-stderr cog plan-mode-gate render --skill demo --bogus

  assert_failure
  [[ $stderr == *"unknown plan-mode-gate render option"* ]]
}

@test "cog plan-mode-gate without a mode fails" {
  run --separate-stderr cog plan-mode-gate

  assert_failure
  [[ $stderr == *"missing plan-mode-gate mode"* ]]
}

@test "cog plan-mode-gate render output passes skill-lint round-trip" {
  mkdir -p "${BATS_TEST_TMPDIR}/skills/claude/executor-demo"
  local file="${BATS_TEST_TMPDIR}/skills/claude/executor-demo/SKILL.md"
  cat >"$file" <<'EOF'
---
name: executor-demo
description: Demo.
---

<!-- trigger-tests: "demo" -->

# Demo

EOF
  cog plan-mode-gate render --skill executor-demo >>"$file"

  run cog skill-lint "$file"

  assert_success
}
