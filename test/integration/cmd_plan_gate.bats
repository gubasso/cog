setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  export XDG_RUNTIME_DIR="${BATS_TEST_TMPDIR}/runtime"
  mkdir -p "$HOME" "$XDG_STATE_HOME" "$XDG_RUNTIME_DIR"
}

write_plan_doc() {
  cat >"$1" <<'EOF'
# Build X

## Goal

Ship X.

## Implementation Plan

1. Change lib/commands/cmd_x.sh.

## Acceptance Criteria

- [ ] just test passes
EOF
}

write_loose_plan() {
  cat >"$1" <<'EOF'
# Migrate the store

## Context

The store is split across two roots.

## Approach

Move the roots, then reconcile.

## Risks

- data loss on partial move
EOF
}

@test "cog plan-gate check passes a plan-doc shaped file" {
  local plan="${BATS_TEST_TMPDIR}/plan.md"
  write_plan_doc "$plan"

  run cog plan-gate check "$plan" --json

  assert_success
  printf '%s\n' "$output" | jq -e \
    '.schema == "cog.plan-gate.v1" and
    .ok == true and
    .mode == "file" and
    .verdict == "plan" and
    (.source_verdicts[0].plan_doc_shape == true) and
    (.missing | length) == 0' >/dev/null
}

@test "cog plan-gate check passes a plan that is not plan-doc shaped" {
  local plan="${BATS_TEST_TMPDIR}/loose.md"
  write_loose_plan "$plan"

  run cog plan-gate check "$plan" --json

  assert_success
  printf '%s\n' "$output" | jq -e \
    '.ok == true and
    .verdict == "plan" and
    (.source_verdicts[0].plan_doc_shape == false) and
    (.matched_sections | index("approach"))' >/dev/null
}

@test "cog plan-gate check rejects a bare prompt with a data error" {
  local prompt="${BATS_TEST_TMPDIR}/prompt.md"
  printf '%s\n' "fix the login bug" >"$prompt"

  run cog plan-gate check "$prompt" --json

  assert_failure 65
  printf '%s\n' "$output" | jq -e \
    '.ok == false and
    .verdict == "insufficient" and
    (.missing | length) > 0 and
    (.reason | test("not a reviewable plan"))' >/dev/null
}

@test "cog plan-gate check rejects a headings-only file with no plan body" {
  local notes="${BATS_TEST_TMPDIR}/notes.md"
  cat >"$notes" <<'EOF'
# Notes

## Context

Some background.
EOF

  run cog plan-gate check "$notes" --json

  assert_failure 65
  printf '%s\n' "$output" | jq -e \
    '.verdict == "insufficient" and
    ([.missing[] | select(test("plan-body section"))] | length) == 1' >/dev/null
}

# The canonical section labels overlap ("phase" and "phases" both match a single
# "## Phases"), so the section floor must count headings, not matched labels.
@test "cog plan-gate check rejects a status surface whose labels overlap" {
  local status="${BATS_TEST_TMPDIR}/status.md"
  cat >"$status" <<'EOF'
# Status

## Phases

Phase one is done.

## Risks

- none
EOF

  run cog plan-gate check "$status" --json

  assert_failure 65
  printf '%s\n' "$output" | jq -e \
    '.verdict == "insufficient" and
    ([.missing[] | select(test("found 2"))] | length) == 1' >/dev/null
}

# Canonical labels are matched on word boundaries, so "Planning Status" is not
# the `plan` section and "Background" is not the `round` section.
@test "cog plan-gate check rejects a status surface whose words merely contain labels" {
  local status="${BATS_TEST_TMPDIR}/planning-status.md"
  cat >"$status" <<'EOF'
# Planning Status

## Context

Where things stand.

## Risks

- slipping
EOF

  run cog plan-gate check "$status" --json

  assert_failure 65
  printf '%s\n' "$output" | jq -e \
    '.verdict == "insufficient" and
    ([.source_verdicts[0].plan_headings[] | select(. == "plan")] | length) == 0' >/dev/null
}

# Heading titles are normalized before deduplication, so one section written
# twice with different casing cannot count twice toward the floor.
@test "cog plan-gate check counts case-varied duplicate headings once" {
  local dup="${BATS_TEST_TMPDIR}/dup.md"
  cat >"$dup" <<'EOF'
# Status

## PHASE

One.

## Phase

Two.

## Risks

- none
EOF

  run cog plan-gate check "$dup" --json

  assert_failure 65
  printf '%s\n' "$output" | jq -e \
    '.verdict == "insufficient" and
    ([.missing[] | select(test("found 2"))] | length) == 1' >/dev/null
}

# A genuine plan that uses numbered phase headings must still clear the floor.
@test "cog plan-gate check passes a plan with numbered phase headings" {
  local plan="${BATS_TEST_TMPDIR}/phased.md"
  cat >"$plan" <<'EOF'
# Ship Y

## Objective

Ship Y.

## Phase 1: Setup

Do the setup.

## Phase 2: Cutover

Do the cutover.

## Verification

Run the tests.
EOF

  run cog plan-gate check "$plan" --json

  assert_success
  printf '%s\n' "$output" | jq -e \
    '.verdict == "plan" and (.matched_sections | index("phase"))' >/dev/null
}

@test "cog plan-gate check rejects an empty file" {
  local empty="${BATS_TEST_TMPDIR}/empty.md"
  : >"$empty"

  run cog plan-gate check "$empty" --json

  assert_failure 65
  printf '%s\n' "$output" | jq -e \
    '.verdict == "insufficient" and (.source_verdicts[0].reason == "file is empty")' >/dev/null
}

@test "cog plan-gate check passes a directory holding one plan among notes" {
  local dir="${BATS_TEST_TMPDIR}/rounds"
  mkdir -p "$dir"
  write_plan_doc "${dir}/round-1.md"
  printf '%s\n' "scratch notes" >"${dir}/notes.md"

  run cog plan-gate check "$dir" --json

  assert_success
  printf '%s\n' "$output" | jq -e \
    '.mode == "dir" and
    .verdict == "plan" and
    (.sources | length) == 2 and
    (.passing_sources | length) == 1' >/dev/null
}

@test "cog plan-gate check rejects a directory of stubs" {
  local dir="${BATS_TEST_TMPDIR}/stubs"
  mkdir -p "$dir"
  printf '%s\n' "todo" >"${dir}/a.md"
  printf '%s\n' "also todo" >"${dir}/b.md"

  run cog plan-gate check "$dir" --json

  assert_failure 65
  printf '%s\n' "$output" | jq -e '.mode == "dir" and .verdict == "insufficient"' >/dev/null
}

@test "cog plan-gate check rejects a directory with no markdown sources" {
  local dir="${BATS_TEST_TMPDIR}/empty-dir"
  mkdir -p "$dir"

  run cog plan-gate check "$dir" --json

  assert_failure 65
  printf '%s\n' "$output" | jq -e \
    '.verdict == "insufficient" and
    (.sources | length) == 0 and
    (.missing[0] | test("markdown plan file"))' >/dev/null
}

@test "cog plan-gate check reads inline text through --input-file" {
  local staged="${BATS_TEST_TMPDIR}/raw-input.txt"
  printf '%s\n' "please review my idea for the login flow" >"$staged"

  run cog plan-gate check --input-file "$staged" --json

  assert_failure 65
  printf '%s\n' "$output" | jq -e '.mode == "inline" and .verdict == "insufficient"' >/dev/null
}

@test "cog plan-gate check accepts an inline staged plan" {
  local staged="${BATS_TEST_TMPDIR}/raw-plan.txt"
  write_plan_doc "$staged"

  run cog plan-gate check --input-file "$staged" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.mode == "inline" and .verdict == "plan"' >/dev/null
}

@test "cog plan-gate check emits human status lines and fails closed" {
  local prompt="${BATS_TEST_TMPDIR}/prompt.md"
  printf '%s\n' "fix the login bug" >"$prompt"

  run --separate-stderr cog plan-gate check "$prompt"

  assert_failure 65
  [[ $output == *"PLAN_GATE=insufficient"* ]]
  [[ $output == *"MODE=file"* ]]
  [[ $output == *"REASON=not a reviewable plan"* ]]
  [[ $stderr == *"err.kind: InvalidInput"* ]]
  [[ $stderr == *"/plan-oneshot"* ]]
}

@test "cog plan-gate check rejects a nonexistent target" {
  run --separate-stderr cog plan-gate check "${BATS_TEST_TMPDIR}/nope.md"

  assert_failure
  [[ $stderr == *"err.kind: InputNotFound"* ]]
}

@test "cog plan-gate check requires an absolute --input-file" {
  run --separate-stderr cog plan-gate check --input-file relative.txt

  assert_failure
  [[ $stderr == *"err.kind: InvalidInput"* ]]
  [[ $stderr == *"must be absolute"* ]]
}

@test "cog plan-gate check rejects both a path and --input-file" {
  local plan="${BATS_TEST_TMPDIR}/plan.md"
  write_plan_doc "$plan"

  run --separate-stderr cog plan-gate check "$plan" --input-file "$plan"

  assert_failure
  [[ $stderr == *"err.kind: InvalidInput"* ]]
}

@test "cog plan-gate requires a mode" {
  run --separate-stderr cog plan-gate

  assert_failure
  [[ $stderr == *"err.kind: MissingArgument"* ]]
}

@test "cog plan-gate rejects an unknown mode" {
  run --separate-stderr cog plan-gate validate

  assert_failure
  [[ $stderr == *"err.kind: InvalidInput"* ]]
}
