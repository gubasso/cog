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
  source "${LIB_DIR}/functions/fn_plan_doc.sh"
  source "${LIB_DIR}/commands/cmd_plan_doc.sh"
}

@test "plan-doc template includes deterministic headings" {
  local research_json='{"root":"/tmp/research","index":"/tmp/research/index.jsonl","exists":false}'

  run cog::fn::plan_doc::template "Lean Plan" /tmp/repo "$research_json"

  assert_success
  assert_output --partial "# Lean Plan"
  assert_output --partial "## Goal"
  assert_output --partial "## Implementation Plan"
  assert_output --partial "## Acceptance Criteria"
}

@test "plan-doc save_json writes default runtime artifact" {
  run cog::fn::plan_doc::save_json "Lean Plan Artifact" /tmp/repo "" ""

  assert_success
  local output_path
  output_path="$(printf '%s\n' "$output" | jq -r '.output_path')"
  [[ $output_path == "$XDG_STATE_HOME"/cog/runs/plan-doc-lean-plan-artifact-*"/lean-plan-artifact.md" ]]
  [ -f "$output_path" ]
}

@test "plan-doc save_json honors absolute output override" {
  local out="${BATS_TEST_TMPDIR}/custom/plan.md"

  run cog::fn::plan_doc::save_json "Override Plan" /tmp/repo "$out" ""

  assert_success
  printf '%s\n' "$output" | jq -e --arg out "$out" '.output_path == $out' >/dev/null
  [ -f "$out" ]
}

@test "plan-doc validate_json passes generated artifact" {
  local out="${BATS_TEST_TMPDIR}/plan.md"
  run cog::fn::plan_doc::save_json "Valid Plan" /tmp/repo "$out" ""
  assert_success

  run cog::fn::plan_doc::validate_json "$out"

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and (.errors | length) == 0' >/dev/null
}

@test "plan-doc validate_json reports missing headings" {
  local out="${BATS_TEST_TMPDIR}/bad.md"
  printf '%s\n' "# Bad" >"$out"

  run cog::fn::plan_doc::validate_json "$out"

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == false and (.errors | length) > 0' >/dev/null
}

@test "plan-doc validate_json rejects an annotated plan review" {
  local review="${BATS_TEST_TMPDIR}/review.md"
  printf '# Annotated Plan Review\n\n## Verdict\n\nMODIFIED\n\n## Annotated Plan\n\n### APPROVED\n\n### MODIFIED\n\n### REMOVED\n\n### ADDED\n' >"$review"
  run cog::fn::plan_doc::validate_json "$review"
  assert_success
  printf '%s\n' "$output" | jq -e '(.ok|not) and (.errors|length)==3' >/dev/null
}

@test "plan-doc command rejects missing title" {
  run --separate-stderr cog::cmd::plan_doc save

  assert_failure 64
  [[ $stderr == *"err.kind: MissingArgument"* ]]
}
