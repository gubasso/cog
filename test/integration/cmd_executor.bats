setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  export XDG_RUNTIME_DIR="${BATS_TEST_TMPDIR}/runtime"
  mkdir -p "$HOME" "$XDG_STATE_HOME" "$XDG_RUNTIME_DIR"
}

@test "cog executor init classifies lean prompt input and returns three stages" {
  run cog executor init --executor executor-lean --engine codex --input "Implement thing" --json

  assert_success
  printf '%s\n' "$output" | jq -e \
    '.schema == "cog.executor.init.v1" and
     .input == {kind: "prompt", value: "Implement thing", plan_path: null} and
     .executor == "executor-lean" and
     .engine == "codex" and
     .plan_engine == "codex" and
     .stages == ["stage1","stage2","stage3"] and
     .review_engine == "claude" and
     .reviewer == "/review-plan-lean" and
     .flow.reviewed == true and
     (.phases | length) == 3 and
     .artifacts.schema == "cog.executor.artifacts.v2"' >/dev/null
  local run_dir
  run_dir="$(printf '%s\n' "$output" | jq -r '.run_dir')"
  [ -d "$run_dir" ]
  assert_file_exists "${run_dir}/request.md"
  assert_file_contains "${run_dir}/executor" "executor-lean"
  assert_file_contains "${run_dir}/engine" "codex"
}

@test "cog executor init classifies lean plan input and skips stage1" {
  local plan="${BATS_TEST_TMPDIR}/plan.md"
  printf '%s\n' "# a plan" >"$plan"

  run cog executor init --executor executor-lean --engine claude --input "$plan" --json

  assert_success
  printf '%s\n' "$output" | jq -e \
    '.input.kind == "plan" and
     .executor == "executor-lean" and
     .engine == "claude" and
     .stages == ["stage2","stage3"] and
     .review_engine == "codex" and
     .reviewer == "/review-plan-lean"' >/dev/null
  local run_dir
  run_dir="$(printf '%s\n' "$output" | jq -r '.run_dir')"
  assert_file_contains "${run_dir}/plan-source" "$plan"
  [ ! -e "${run_dir}/stage1-plan.md" ]
}

@test "cog executor init classifies single prompt input and returns two stages" {
  run cog executor init --executor executor-single --engine codex --input "Implement thing" --json

  assert_success
  printf '%s\n' "$output" | jq -e \
    '.schema == "cog.executor.init.v1" and
     .executor == "executor-single" and
     .engine == "codex" and
     .plan_engine == "codex" and
     .review_engine == "none" and
     .reviewer == "none" and
     .flow.reviewed == false and
     .stages == ["stage1","stage2"] and
     .phases[1].phase == "execution" and
     .phases[1].artifact == "stage2-execution.md" and
     .artifacts.schema == "cog.executor.artifacts.v2"' >/dev/null
}

@test "cog executor init classifies single plan input and skips plan phase" {
  local plan="${BATS_TEST_TMPDIR}/plan.md"
  printf '%s\n' "# a plan" >"$plan"

  run cog executor init --executor executor-single --engine claude --input "$plan" --json

  assert_success
  printf '%s\n' "$output" | jq -e \
    '.input.kind == "plan" and
     .executor == "executor-single" and
     .engine == "claude" and
     .stages == ["stage2"] and
     .reviewer == "none" and
     .phases[1].artifact == "stage2-execution.md"' >/dev/null
}

@test "cog executor init rejects removed plan-engine option" {
  run --separate-stderr cog executor init --executor executor-lean --engine claude --input "x" --plan-engine claude

  assert_failure
  [[ $stderr == *"unknown executor init option"* ]]
  [[ $stderr == *"--plan-engine"* ]]
}

@test "cog executor select-reviewer applies flow and engine table" {
  run cog executor select-reviewer --executor executor-lean --engine claude --json
  assert_success
  printf '%s\n' "$output" | jq -e \
    '.plan_engine == "claude" and .review_engine == "codex" and .reviewer == "/review-plan-lean"' >/dev/null

  run cog executor select-reviewer --executor executor-lean --engine codex --json
  assert_success
  printf '%s\n' "$output" | jq -e \
    '.plan_engine == "codex" and .review_engine == "claude" and .reviewer == "/review-plan-lean"' >/dev/null

  run cog executor select-reviewer --executor executor-single --engine codex --json
  assert_success
  printf '%s\n' "$output" | jq -e \
    '.plan_engine == "codex" and .review_engine == "none" and .reviewer == "none"' >/dev/null
}

@test "cog executor select-reviewer rejects removed plan-engine option" {
  run --separate-stderr cog executor select-reviewer --plan-engine claude --json

  assert_failure
  [[ $stderr == *"unknown select-reviewer option"* ]]
  [[ $stderr == *"--plan-engine"* ]]
}

@test "cog executor classify-input treats missing md path as prompt without stages" {
  run cog executor classify-input "missing.md" --json

  assert_success
  printf '%s\n' "$output" | jq -e \
    '.kind == "prompt" and .value == "missing.md" and .plan_path == null and (has("stages") | not)' >/dev/null
}

@test "cog executor artifacts returns lean phase-keyed canonical paths" {
  local run_dir
  run_dir="$(cog executor init --executor executor-lean --engine claude --input "Implement thing" --json | jq -r '.run_dir')"

  run cog executor artifacts "$run_dir" --json

  assert_success
  printf '%s\n' "$output" | jq -e \
    '.schema == "cog.executor.artifacts.v2" and
     .executor == "executor-lean" and
     (.phases | length) == 3 and
     .phases[0].path == "'"${run_dir}"'/stage1-plan.md" and
     .phases[1].path == "'"${run_dir}"'/stage2-reviewed-plan.md" and
     .phases[2].path == "'"${run_dir}"'/stage3-execution.md" and
     .summary == "'"${run_dir}"'/executor-summary.json"' >/dev/null
}

@test "cog executor artifacts returns single phase-keyed canonical paths" {
  local run_dir
  run_dir="$(cog executor init --executor executor-single --engine codex --input "Implement thing" --json | jq -r '.run_dir')"

  run cog executor artifacts "$run_dir" --json

  assert_success
  printf '%s\n' "$output" | jq -e \
    '.schema == "cog.executor.artifacts.v2" and
     .executor == "executor-single" and
     (.phases | length) == 2 and
     .phases[0].path == "'"${run_dir}"'/stage1-plan.md" and
     .phases[1].path == "'"${run_dir}"'/stage2-execution.md" and
     .summary == "'"${run_dir}"'/executor-summary.json"' >/dev/null
}

@test "cog executor artifacts rejects uninitialized directory" {
  local run_dir="${BATS_TEST_TMPDIR}/run"
  mkdir -p "$run_dir"

  run --separate-stderr cog executor artifacts "$run_dir" --json

  assert_failure
  [[ $stderr == *"InvalidInput"* ]]
  [[ $stderr == *"not initialized"* ]]
}

@test "cog executor queue-prompts emits recognition data" {
  run cog executor queue-prompts --json

  assert_success
  printf '%s\n' "$output" | jq -e \
    '.schema == "cog.executor.queue-prompts.v1" and (.prompts | length) == 5' >/dev/null
  printf '%s\n' "$output" | jq -e \
    '[.prompts[].slash] as $s |
     ($s | index("/executor-prex")) and
     ($s | index("/executor-lean")) and
     ($s | index("/executor-lean-codex")) and
     ($s | index("/executor-single")) and
     ($s | index("/executor-single-codex"))' >/dev/null
  printf '%s\n' "$output" | jq -e \
    '.match.namespace == "executor" and .match.target_argument == "-ar" and (.match.aliases | length) == 0' >/dev/null
}

@test "cog executor summary writes lean v2 JSON in json mode" {
  local run_dir
  run_dir="$(cog executor init --executor executor-lean --engine codex --input "Implement thing" --json | jq -r '.run_dir')"

  run cog executor summary --run-dir "$run_dir" --executor executor-lean --engine codex \
    --input-kind prompt --reviewer /review-plan-lean \
    --stage1 "done" --stage2 "done" --stage3 "done" --json

  assert_success
  printf '%s\n' "$output" | jq -e \
    '.schema == "cog.executor.summary.v2" and
     .ok == true and
     .executor == "executor-lean" and
     .engine == "codex" and
     .review_engine == "claude" and
     .stages.stage1.status == "done" and
     .stages.stage2.phase == "review" and
     .stages.stage3.artifact == "stage3-execution.md" and
     .reviewer == "/review-plan-lean"' >/dev/null
  assert_file_exists "${run_dir}/executor-summary.json"
}

@test "cog executor summary writes single v2 JSON in json mode" {
  local run_dir
  run_dir="$(cog executor init --executor executor-single --engine codex --input "Implement thing" --json | jq -r '.run_dir')"

  run cog executor summary --run-dir "$run_dir" --executor executor-single --engine codex \
    --input-kind prompt --reviewer none \
    --stage1 "done" --stage2 "done" --json

  assert_success
  printf '%s\n' "$output" | jq -e \
    '.schema == "cog.executor.summary.v2" and
     .ok == true and
     .executor == "executor-single" and
     .engine == "codex" and
     .review_engine == "none" and
     .reviewer == "none" and
     .stages.stage1.phase == "plan" and
     .stages.stage2.phase == "execution" and
     .stages.stage2.artifact == "stage2-execution.md"' >/dev/null
  assert_file_exists "${run_dir}/executor-summary.json"
}

@test "cog executor summary prints RESOLVED in non-JSON mode" {
  local run_dir
  run_dir="$(cog executor init --executor executor-lean --engine claude --input "Implement thing" --json | jq -r '.run_dir')"

  run cog executor summary --run-dir "$run_dir" --executor executor-lean --engine claude \
    --input-kind prompt --reviewer /review-plan-lean \
    --stage1 "done" --stage2 "done" --stage3 "done"

  assert_success
  [[ $output == *"RESOLVED ${run_dir}/executor-summary.json"* ]]
}

@test "cog executor summary rejects an unknown reviewer" {
  local run_dir
  run_dir="$(cog executor init --executor executor-lean --engine codex --input "Implement thing" --json | jq -r '.run_dir')"

  run --separate-stderr cog executor summary --run-dir "$run_dir" --executor executor-lean --engine codex \
    --input-kind prompt --reviewer /review-plan-other \
    --stage1 "done" --stage2 "done" --stage3 "done"

  assert_failure
  [[ $stderr == *"invalid executor reviewer"* ]]
}

@test "cog executor summary rejects removed plan-engine option" {
  local run_dir
  run_dir="$(cog executor init --executor executor-lean --engine codex --input "Implement thing" --json | jq -r '.run_dir')"

  run --separate-stderr cog executor summary --run-dir "$run_dir" --executor executor-lean --engine codex \
    --input-kind prompt --plan-engine codex --reviewer /review-plan-lean \
    --stage1 "done" --stage2 "done" --stage3 "done"

  assert_failure
  [[ $stderr == *"unknown summary option"* ]]
  [[ $stderr == *"--plan-engine"* ]]
}

@test "cog executor --help dispatches" {
  run cog executor --help

  assert_success
  [[ $output == *"Usage: cog executor"* ]]
  [[ $output == *"Manage shared executor run contracts and stage artifacts."* ]]
}
