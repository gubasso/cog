setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
}

# --- render ---------------------------------------------------------------

@test "cog gate render --id plan-mode emits the canonical plan-mode stanza" {
  run cog gate render --id plan-mode --skill demo

  assert_success
  # shellcheck disable=SC2016
  expected='<!-- cog-plan-mode-gate -->

**Phase 0 — Plan-mode gate.** If Claude Code **plan mode** is active (a system-reminder says plan
mode is on / that you must not make edits), **STOP** before any other work — parsing args,
researching, interviewing, delegating, or writing. Tell the user in one line to exit plan mode
(`Shift+Tab`) and re-invoke `/demo`. Do not call `ExitPlanMode`, and do not silently continue.'
  assert_output "$expected"
}

@test "cog gate render --id context-brief emits the canonical context-brief stanza" {
  run cog gate render --id context-brief --skill demo

  assert_success
  # shellcheck disable=SC2016
  expected='<!-- cog-context-brief-gate -->

**Context-brief gate.** Before `/demo` dispatches to any fresh-context worker — an Agent subagent
or a `cog codex-runner` Codex job — build its input as a validated context brief from your whole
accumulated raw context: attach the raw request as-is, author an oriented objective, carry the full
substance and load-bearing artifacts, and omit your own verdict. Build the brief with `cog
context-brief build` and confirm it with `cog context-brief validate` before dispatch.'
  assert_output "$expected"
}

@test "cog gate render substitutes the skill name into the stanza" {
  run cog gate render --id plan-mode --skill review-plan-oneshot

  assert_success
  # shellcheck disable=SC2016
  assert_output --partial 're-invoke `/review-plan-oneshot`'
}

@test "cog gate render fails without --id" {
  run --separate-stderr cog gate render --skill demo

  assert_failure
  [[ $stderr == *"missing gate id"* ]]
}

@test "cog gate render rejects an unknown --id" {
  run --separate-stderr cog gate render --id bogus --skill demo

  assert_failure
  [[ $stderr == *"unknown gate id"* ]]
}

@test "cog gate render fails without --skill" {
  run --separate-stderr cog gate render --id plan-mode

  assert_failure
  [[ $stderr == *"skill name"* ]]
}

@test "cog gate render rejects an invalid skill name" {
  run --separate-stderr cog gate render --id plan-mode --skill "Bad Name"

  assert_failure
  [[ $stderr == *"invalid skill name"* ]]
}

@test "cog gate render rejects an unknown option" {
  run --separate-stderr cog gate render --id plan-mode --skill demo --bogus

  assert_failure
  [[ $stderr == *"unknown gate render option"* ]]
}

# --- list -----------------------------------------------------------------

@test "cog gate list reports both gate ids" {
  run cog gate list

  assert_success
  assert_output --partial 'plan-mode'
  assert_output --partial 'context-brief'
}

@test "cog gate list --format json emits an array of ids" {
  run cog gate list --format json

  assert_success
  assert_output --partial '"id":"plan-mode"'
  assert_output --partial '"id":"context-brief"'
}

# --- check ----------------------------------------------------------------

@test "cog gate check passes for an up-to-date stanza" {
  local file="${BATS_TEST_TMPDIR}/gate.md"
  cog gate render --id plan-mode --skill demo >"$file"

  run cog gate check --id plan-mode --skill demo --input "$file"

  assert_success
  assert_output --partial 'ok plan-mode demo'
}

@test "cog gate check --format json reports ok true" {
  local file="${BATS_TEST_TMPDIR}/gate.md"
  cog gate render --id context-brief --skill demo >"$file"

  run cog gate check --id context-brief --skill demo --input "$file" --format json

  assert_success
  assert_output --partial '"ok":true'
  assert_output --partial '"status":"ok"'
}

@test "cog gate check fails on drift" {
  local file="${BATS_TEST_TMPDIR}/gate.md"
  cog gate render --id plan-mode --skill demo >"$file"

  # Drift: the stanza is rendered for a different skill name.
  run cog gate check --id plan-mode --skill other --input "$file"

  assert_failure
  assert_output --partial 'drift plan-mode other'
}

@test "cog gate check reports missing when the marker has no stanza" {
  local file="${BATS_TEST_TMPDIR}/gate.md"
  printf '<!-- cog-plan-mode-gate -->\n' >"$file"

  run cog gate check --id plan-mode --skill demo --input "$file"

  assert_failure
  assert_output --partial 'missing plan-mode demo'
}

# --- stamp ----------------------------------------------------------------

@test "cog gate stamp appends a canonical block when the marker is absent" {
  local file="${BATS_TEST_TMPDIR}/skill.md"
  printf '# Demo\n\nintro\n' >"$file"

  run cog gate stamp --id plan-mode --skill demo --input "$file"
  assert_success
  assert_output --partial "STAMPED ${file}"

  run cog gate check --id plan-mode --skill demo --input "$file"
  assert_success
}

@test "cog gate stamp is idempotent and corrects drift in place" {
  local file="${BATS_TEST_TMPDIR}/skill.md"
  cat >"$file" <<'EOF'
# Demo

<!-- cog-plan-mode-gate -->

**Phase 0 — Plan-mode gate.** OLD DRIFTED WORDING that
spans two lines.

## Next

trailing content preserved
EOF

  cog gate stamp --id plan-mode --skill demo --input "$file"
  cp "$file" "${file}.once"
  cog gate stamp --id plan-mode --skill demo --input "$file"

  run diff "$file" "${file}.once"
  assert_success

  run cog gate check --id plan-mode --skill demo --input "$file"
  assert_success

  run grep -q 'trailing content preserved' "$file"
  assert_success

  run grep -q 'OLD DRIFTED' "$file"
  assert_failure
}

# --- dispatch -------------------------------------------------------------

@test "cog gate without a verb shows usage" {
  run cog gate

  assert_success
  assert_output --partial 'Usage: cog gate render --id <id> --skill <name>'
}

@test "cog gate rejects an unknown verb" {
  run --separate-stderr cog gate frobnicate

  assert_failure
  [[ $stderr == *"unknown gate mode"* ]]
}

@test "cog gate render output passes skill-lint round-trip" {
  mkdir -p "${BATS_TEST_TMPDIR}/skills/claude/executor-demo"
  local file="${BATS_TEST_TMPDIR}/skills/claude/executor-demo/SKILL.md"
  cat >"$file" <<'EOF'
---
name: executor-demo
description: Demo.
model: opus
effort: medium
---

<!-- trigger-tests: "demo" -->

# Demo

EOF
  cog gate render --id plan-mode --skill executor-demo >>"$file"

  run cog skill-lint "$file"

  assert_success
}
