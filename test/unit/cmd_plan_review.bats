setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export LIB_DIR="${BATS_TEST_DIRNAME}/../../lib"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  mkdir -p "$HOME" "$XDG_STATE_HOME"
  source "${LIB_DIR}/helpers.sh"
  source "${LIB_DIR}/functions/fn_ui_print.sh"
  source "${LIB_DIR}/functions/fn_log.sh"
  source "${LIB_DIR}/functions/fn_error_raise.sh"
  source "${LIB_DIR}/functions/fn_json_write.sh"
  source "${LIB_DIR}/functions/fn_rundir.sh"
  source "${LIB_DIR}/functions/fn_data.sh"
  source "${LIB_DIR}/functions/fn_research.sh"
  source "${LIB_DIR}/functions/fn_plan_slug.sh"
  source "${LIB_DIR}/functions/fn_plan_artifact.sh"
  source "${LIB_DIR}/functions/fn_plan_review.sh"
  source "${LIB_DIR}/commands/cmd_plan_review.sh"
}

write_inputs() {
  PLAN_INPUT="${BATS_TEST_TMPDIR}/input-plan.md"
  REQUEST_INPUT="${BATS_TEST_TMPDIR}/request.md"
  printf '%s\n' "# Plan" >"$PLAN_INPUT"
  printf '%s\n' "# Request" >"$REQUEST_INPUT"
}

@test "plan-review template includes review vocabulary" {
  local research_json='{"root":"/tmp/research","index":"/tmp/research/index.jsonl","exists":false}'

  run cog::fn::plan_review::template /tmp/plan.md /tmp/request.md /tmp/repo "$research_json"

  assert_success
  assert_output --partial "APPROVED"
  assert_output --partial "MODIFIED"
  assert_output --partial "REMOVED"
  assert_output --partial "ADDED"
}

@test "plan-review save_json rejects relative input paths" {
  run --separate-stderr cog::fn::plan_review::save_json relative.md /tmp/request.md "" /tmp/repo ""

  assert_failure 65
  [[ $stderr == *"err.kind: InvalidInput"* ]]
}

@test "plan-review save_json writes default runtime artifact" {
  write_inputs

  run cog::fn::plan_review::save_json "$PLAN_INPUT" "$REQUEST_INPUT" "" /tmp/repo ""

  assert_success
  local output_path
  output_path="$(printf '%s\n' "$output" | jq -r '.output_path')"
  [[ $output_path == "$XDG_STATE_HOME"/cog/runs/plan-review-input-plan-md-*"/input-plan-md.md" ]]
  [ -f "$output_path" ]
}

@test "plan-review save_json honors absolute output override" {
  write_inputs
  local out="${BATS_TEST_TMPDIR}/review/out.md"

  run cog::fn::plan_review::save_json "$PLAN_INPUT" "$REQUEST_INPUT" "$out" /tmp/repo ""

  assert_success
  printf '%s\n' "$output" | jq -e --arg out "$out" '.output_path == $out' >/dev/null
  [ -f "$out" ]
}

@test "plan-review orchestrator_json writes three-path artifact" {
  write_inputs
  local out="${BATS_TEST_TMPDIR}/review/orchestrator.md"

  run cog::fn::plan_review::orchestrator_json "$PLAN_INPUT" "$REQUEST_INPUT" "$out"

  assert_success
  printf '%s\n' "$output" | jq -e --arg out "$out" '.action == "orchestrator" and .output_path == $out' >/dev/null
  [ -f "$out" ]
}

@test "plan-review validate_json passes generated artifact" {
  write_inputs
  local out="${BATS_TEST_TMPDIR}/review.md"
  run cog::fn::plan_review::save_json "$PLAN_INPUT" "$REQUEST_INPUT" "$out" /tmp/repo ""
  assert_success

  run cog::fn::plan_review::validate_json "$out"

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and (.errors | length) == 0' >/dev/null
}

@test "plan-review validate_json reports missing vocabulary" {
  local out="${BATS_TEST_TMPDIR}/bad.md"
  printf '%s\n' "# Annotated Plan Review" "## Verdict" >"$out"

  run cog::fn::plan_review::validate_json "$out"

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == false and (.errors | length) > 0' >/dev/null
}
