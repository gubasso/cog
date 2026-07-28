setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  export XDG_RUNTIME_DIR="${BATS_TEST_TMPDIR}/runtime"
  mkdir -p "$HOME" "$XDG_STATE_HOME" "$XDG_RUNTIME_DIR"
}

@test "cog assess-input facts detects plan-section headings in a rich plan" {
  local plan="${BATS_TEST_TMPDIR}/rich.md"
  cat >"$plan" <<'EOF'
# Build X
## Goal
Ship X.
## Implementation Plan
1. step
## Acceptance Criteria
- works
## Risks
- none
EOF

  run cog assess-input facts --file "$plan" --json

  assert_success
  printf '%s\n' "$output" | jq -e \
    '.schema == "cog.assess-input.facts.v1" and
    .ok == true and
    .totals.plan_files == 1 and
    .totals.readable_plan_files == 1 and
    .totals.max_heading_count >= 4 and
    (.files[0].plan_headings | index("goal")) and
    (.files[0].plan_headings | index("acceptance criteria"))' >/dev/null
}

@test "cog assess-input facts reports a thin file with no plan headings" {
  local thin="${BATS_TEST_TMPDIR}/thin.md"
  printf '%s\n' "just do the thing" >"$thin"

  run cog assess-input facts --file "$thin" --json

  assert_success
  printf '%s\n' "$output" | jq -e \
    '.totals.max_heading_count == 0 and (.files[0].plan_headings | length) == 0' >/dev/null
}

@test "cog assess-input record persists and validates a verdict" {
  local run_dir
  run_dir="$(cog rundir assess-test | sed 's/RUN_DIR=//')"

  run cog assess-input record --run-dir "$run_dir" --route good-input --confidence high \
    --rationale "rich multi-section plan" --signal max_heading_count=5 --signal plan_files=1 --json

  assert_success
  printf '%s\n' "$output" | jq -e \
    '.schema == "cog.assess-input.v1" and
    .ok == true and
    .route == "good-input" and
    .good_input == true and
    .confidence == "high" and
    .signals.max_heading_count == "5"' >/dev/null
  assert_file_exists "${run_dir}/assess-input.json"

  run cog assess-input validate "${run_dir}/assess-input.json" --json
  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true' >/dev/null
}

@test "cog assess-input record marks needs-plan with good_input false" {
  local run_dir
  run_dir="$(cog rundir assess-test | sed 's/RUN_DIR=//')"

  run cog assess-input record --run-dir "$run_dir" --route needs-plan --confidence low \
    --rationale "bare prompt" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.route == "needs-plan" and .good_input == false' >/dev/null
}

@test "cog assess-input record rejects an invalid route" {
  local run_dir
  run_dir="$(cog rundir assess-test | sed 's/RUN_DIR=//')"

  run --separate-stderr cog assess-input record --run-dir "$run_dir" --route maybe \
    --confidence high --rationale x

  assert_failure
  [[ $stderr == *"invalid assess-input route"* ]]
}

@test "cog assess-input record rejects an invalid confidence" {
  local run_dir
  run_dir="$(cog rundir assess-test | sed 's/RUN_DIR=//')"

  run --separate-stderr cog assess-input record --run-dir "$run_dir" --route good-input \
    --confidence certain --rationale x

  assert_failure
  [[ $stderr == *"invalid assess-input confidence"* ]]
}

@test "cog assess-input validate fails on a missing verdict" {
  run --separate-stderr cog assess-input validate "${BATS_TEST_TMPDIR}/nope.json" --json

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false' >/dev/null
}

@test "cog assess-input --help dispatches" {
  run cog assess-input --help

  assert_success
  [[ $output == *"Usage: cog assess-input"* ]]
}
