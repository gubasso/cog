setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  export XDG_RUNTIME_DIR="${BATS_TEST_TMPDIR}/runtime"
  mkdir -p "$HOME" "$XDG_STATE_HOME" "$XDG_RUNTIME_DIR"
}

@test "cog executor init classifies prompt input and returns three stages" {
  run cog executor init --executor codex-session --input "Implement thing" --json

  assert_success
  printf '%s\n' "$output" | jq -e \
    '.input == {kind: "prompt", value: "Implement thing", plan_path: null} and
     .stages == ["stage1","stage2","stage3"] and
     .plan_engine == "codex" and
     .reviewer == "/review-plan-claude"' >/dev/null
  local run_dir
  run_dir="$(printf '%s\n' "$output" | jq -r '.run_dir')"
  [ -d "$run_dir" ]
  assert_file_exists "${run_dir}/request.md"
}

@test "cog executor init classifies plan input and skips stage1" {
  local plan="${BATS_TEST_TMPDIR}/plan.md"
  printf '%s\n' "# a plan" >"$plan"

  run cog executor init --executor claude --input "$plan" --plan-engine claude --json

  assert_success
  printf '%s\n' "$output" | jq -e \
    '.input.kind == "plan" and
     .stages == ["stage2","stage3"] and
     .reviewer == "/review-plan-codex"' >/dev/null
  local run_dir
  run_dir="$(printf '%s\n' "$output" | jq -r '.run_dir')"
  assert_file_contains "${run_dir}/plan-source" "$plan"
  [ ! -e "${run_dir}/stage1-plan.md" ]
}

@test "cog executor init requires plan engine for plan input" {
  local plan="${BATS_TEST_TMPDIR}/plan.md"
  printf '%s\n' "# a plan" >"$plan"

  run --separate-stderr cog executor init --executor claude --input "$plan"

  assert_failure
  [[ $stderr == *"plan input requires --plan-engine"* ]]
}

@test "cog executor select-reviewer applies the other-engine table" {
  run cog executor select-reviewer --plan-engine claude --json
  assert_success
  printf '%s\n' "$output" | jq -e \
    '.review_engine == "codex" and .reviewer == "/review-plan-codex"' >/dev/null

  run cog executor select-reviewer --plan-engine codex --json
  assert_success
  printf '%s\n' "$output" | jq -e \
    '.review_engine == "claude" and .reviewer == "/review-plan-claude"' >/dev/null
}

@test "cog executor classify-input treats missing md path as prompt" {
  run cog executor classify-input "missing.md" --json

  assert_success
  printf '%s\n' "$output" | jq -e \
    '.kind == "prompt" and .stages == ["stage1","stage2","stage3"]' >/dev/null
}

@test "cog executor artifacts returns canonical paths" {
  local run_dir="${BATS_TEST_TMPDIR}/run"
  mkdir -p "$run_dir"

  run cog executor artifacts "$run_dir" --json

  assert_success
  printf '%s\n' "$output" | jq -e \
    '.stage1_plan == "'"${run_dir}"'/stage1-plan.md" and
     .stage2_reviewed_plan == "'"${run_dir}"'/stage2-reviewed-plan.md" and
     .stage3_execution == "'"${run_dir}"'/stage3-execution.md" and
     .summary == "'"${run_dir}"'/executor-summary.json"' >/dev/null
}

@test "cog executor queue-prompts emits recognition data" {
  run cog executor queue-prompts --json

  assert_success
  printf '%s\n' "$output" | jq -e \
    '.schema == "cog.executor.queue-prompts.v1" and (.prompts | length) == 3' >/dev/null
  printf '%s\n' "$output" | jq -e \
    '[.prompts[].slash] as $s | ($s | index("/executor-prex")) and ($s | index("/executor-claude")) and ($s | index("/executor-codex-session"))' >/dev/null
}

@test "cog executor summary writes file-first and emits pure JSON in --json mode" {
  local run_dir="${BATS_TEST_TMPDIR}/summary-run"
  mkdir -p "$run_dir"

  run cog executor summary --run-dir "$run_dir" --executor codex-session \
    --input-kind prompt --plan-engine codex --reviewer /review-plan-claude \
    --stage1 "done" --stage2 "done" --stage3 "done" --json

  assert_success
  # Stdout must be parseable as a single JSON object (no leading RESOLVED line).
  printf '%s\n' "$output" | jq -e \
    '.schema == "cog.executor.summary.v1" and
     .stages.stage1.status == "done" and
     .reviewer == "/review-plan-claude"' >/dev/null
  assert_file_exists "${run_dir}/executor-summary.json"
}

@test "cog executor summary prints RESOLVED in non-JSON mode" {
  local run_dir="${BATS_TEST_TMPDIR}/summary-run-text"
  mkdir -p "$run_dir"

  run cog executor summary --run-dir "$run_dir" --executor claude \
    --input-kind plan --plan-engine claude --reviewer /review-plan-codex \
    --stage1 "skipped" --stage2 "done" --stage3 "done"

  assert_success
  [[ $output == *"RESOLVED ${run_dir}/executor-summary.json"* ]]
}

@test "cog executor summary rejects a reviewer that violates the other-engine table" {
  local run_dir="${BATS_TEST_TMPDIR}/summary-bad"
  mkdir -p "$run_dir"

  run --separate-stderr cog executor summary --run-dir "$run_dir" --executor codex-session \
    --input-kind prompt --plan-engine codex --reviewer /review-plan-codex \
    --stage1 "done" --stage2 "done" --stage3 "done"

  assert_failure
  [[ $stderr == *"reviewer does not match the other-engine table"* ]]
}

@test "cog executor --help dispatches" {
  run cog executor --help

  assert_success
  [[ $output == *"Usage: cog executor"* ]]
}
