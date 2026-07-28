setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  export XDG_RUNTIME_DIR="${BATS_TEST_TMPDIR}/runtime"
  mkdir -p "$HOME" "$XDG_STATE_HOME" "$XDG_RUNTIME_DIR"
}

write_required_inputs() {
  local run_dir="$1"
  mkdir -p "$run_dir"
  printf '%s' "task text" >"${run_dir}/request.md"
  printf '%s' "reviewed plan text" >"${run_dir}/vetted-plan.md"
  printf '%s' "stage 4 review text" >"${run_dir}/review.md"
}

write_thread_ids() {
  local run_dir="$1"
  printf '%s\n' "plan-thread-1" >"${run_dir}/plan-thread-id"
  printf '%s\n' "impl-thread-1" >"${run_dir}/impl-thread-id"
}

@test "cog review-loop-input build writes review_loop_input.json" {
  local run_dir="${BATS_TEST_TMPDIR}/run"
  write_required_inputs "$run_dir"
  write_thread_ids "$run_dir"

  run cog review-loop-input build --run-dir "$run_dir"

  assert_success
  assert_output "RESOLVED ${run_dir}/review_loop_input.json"
  jq -e \
    '.task == "task text" and
    .reviewed_plan == "reviewed plan text" and
    .implementation_review == "stage 4 review text" and
    .plan_thread_id == "plan-thread-1" and
    .impl_thread_id == "impl-thread-1"' \
    "${run_dir}/review_loop_input.json" >/dev/null
}

@test "cog review-loop-input build --json emits schema without writing" {
  local run_dir="${BATS_TEST_TMPDIR}/run"
  write_required_inputs "$run_dir"
  write_thread_ids "$run_dir"

  run cog review-loop-input build --run-dir "$run_dir" --json

  assert_success
  [ ! -e "${run_dir}/review_loop_input.json" ]
  printf '%s\n' "$output" | jq -e \
    'has("task") and has("reviewed_plan") and has("implementation_review") and
    has("plan_thread_id") and has("impl_thread_id")' >/dev/null
}

@test "cog review-loop-input validate accepts valid input" {
  local run_dir="${BATS_TEST_TMPDIR}/run"
  write_required_inputs "$run_dir"
  write_thread_ids "$run_dir"
  cog review-loop-input build --run-dir "$run_dir" >/dev/null

  run cog review-loop-input validate --input "${run_dir}/review_loop_input.json" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .input == "'"${run_dir}/review_loop_input.json"'"' >/dev/null
}

@test "cog review-loop-input build includes the optional context brief verbatim" {
  local run_dir="${BATS_TEST_TMPDIR}/run"
  write_required_inputs "$run_dir"
  write_thread_ids "$run_dir"
  printf '# Context Brief\n\nverbatim brief body\n' >"${run_dir}/context-brief.md"

  run cog review-loop-input build --run-dir "$run_dir" --context "${run_dir}/context-brief.md" --json

  assert_success
  printf '%s\n' "$output" | jq -e \
    '.context == "# Context Brief\n\nverbatim brief body\n"' >/dev/null
}

@test "cog review-loop-input validate accepts the 6-key shape with context" {
  local run_dir="${BATS_TEST_TMPDIR}/run"
  write_required_inputs "$run_dir"
  write_thread_ids "$run_dir"
  printf '# Context Brief\n\nbody\n' >"${run_dir}/context-brief.md"
  cog review-loop-input build --run-dir "$run_dir" --context "${run_dir}/context-brief.md" >/dev/null

  run cog review-loop-input validate --input "${run_dir}/review_loop_input.json" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true' >/dev/null
}

@test "cog review-loop-input validate rejects an empty context value" {
  local input="${BATS_TEST_TMPDIR}/review_loop_input.json"
  jq -n \
    --arg task "task text" \
    --arg reviewed_plan "reviewed plan text" \
    --arg implementation_review "stage 4 review text" \
    '{
      task: $task,
      reviewed_plan: $reviewed_plan,
      implementation_review: $implementation_review,
      plan_thread_id: null,
      impl_thread_id: null,
      context: ""
    }' >"$input"

  run --separate-stderr cog review-loop-input validate --input "$input" --json

  assert_failure
  [[ $stderr == *"review-loop input failed schema validation"* ]]
}

@test "cog review-loop-input validate rejects an unexpected sixth key" {
  local input="${BATS_TEST_TMPDIR}/review_loop_input.json"
  jq -n \
    --arg task "task text" \
    --arg reviewed_plan "reviewed plan text" \
    --arg implementation_review "stage 4 review text" \
    '{
      task: $task,
      reviewed_plan: $reviewed_plan,
      implementation_review: $implementation_review,
      plan_thread_id: null,
      impl_thread_id: null,
      surprise: "nope"
    }' >"$input"

  run --separate-stderr cog review-loop-input validate --input "$input" --json

  assert_failure
  [[ $stderr == *"review-loop input failed schema validation"* ]]
}

@test "cog review-loop-input build fails when required file is missing" {
  local run_dir="${BATS_TEST_TMPDIR}/run"
  write_required_inputs "$run_dir"
  rm -f "${run_dir}/review.md"

  run --separate-stderr cog review-loop-input build --run-dir "$run_dir"

  assert_failure
  [[ $stderr == *"err.kind: InputUnreadable"* ]]
}

@test "cog review-loop-input build fails when required file is empty" {
  local run_dir="${BATS_TEST_TMPDIR}/run"
  write_required_inputs "$run_dir"
  : >"${run_dir}/vetted-plan.md"

  run --separate-stderr cog review-loop-input build --run-dir "$run_dir"

  assert_failure
  [[ $stderr == *"err.kind: InputUnreadable"* ]]
}

@test "cog review-loop-input build treats missing thread ids as null" {
  local run_dir="${BATS_TEST_TMPDIR}/run"
  write_required_inputs "$run_dir"

  run cog review-loop-input build --run-dir "$run_dir" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.plan_thread_id == null and .impl_thread_id == null' >/dev/null
}

@test "cog review-loop-input build fails when thread id file is empty" {
  local run_dir="${BATS_TEST_TMPDIR}/run"
  write_required_inputs "$run_dir"
  : >"${run_dir}/plan-thread-id"

  run --separate-stderr cog review-loop-input build --run-dir "$run_dir"

  assert_failure
  [[ $stderr == *"err.kind: InvalidInput"* ]]
}

@test "cog review-loop-input validate rejects empty thread id" {
  local input="${BATS_TEST_TMPDIR}/review_loop_input.json"
  jq -n \
    --arg task "task text" \
    --arg reviewed_plan "reviewed plan text" \
    --arg implementation_review "stage 4 review text" \
    '{
      task: $task,
      reviewed_plan: $reviewed_plan,
      implementation_review: $implementation_review,
      plan_thread_id: "",
      impl_thread_id: null
    }' >"$input"

  run --separate-stderr cog review-loop-input validate --input "$input" --json

  assert_failure
  [[ $stderr == *"review-loop input failed schema validation"* ]]
}

@test "cog review-loop-input validate rejects malformed thread id" {
  local input="${BATS_TEST_TMPDIR}/review_loop_input.json"
  jq -n \
    --arg task "task text" \
    --arg reviewed_plan "reviewed plan text" \
    --arg implementation_review "stage 4 review text" \
    '{
      task: $task,
      reviewed_plan: $reviewed_plan,
      implementation_review: $implementation_review,
      plan_thread_id: "bad id",
      impl_thread_id: null
    }' >"$input"

  run --separate-stderr cog review-loop-input validate --input "$input" --json

  assert_failure
  [[ $stderr == *"review-loop input failed schema validation"* ]]
}
