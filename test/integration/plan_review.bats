setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  mkdir -p "$HOME" "$XDG_STATE_HOME"
  PLAN_INPUT="${BATS_TEST_TMPDIR}/input-plan.md"
  REQUEST_INPUT="${BATS_TEST_TMPDIR}/request.md"
  printf '%s\n' "# Plan" >"$PLAN_INPUT"
  printf '%s\n' "# Request" >"$REQUEST_INPUT"
}

@test "cog plan-review --help prints usage" {
  run cog plan-review --help

  assert_success
  [[ $output == *"Usage: cog plan-review"* ]]
}

@test "cog plan-review save writes default runtime artifact" {
  run cog plan-review save --plan "$PLAN_INPUT" --request "$REQUEST_INPUT"

  assert_success
  assert_line --regexp '^PLAN_REVIEW_PATH=.*input-plan-md\.md$'
  local output_path="${output#PLAN_REVIEW_PATH=}"
  [[ $output_path == "$XDG_STATE_HOME"/cog/plan-artifacts/plan-review-input-plan-md-*"/input-plan-md.md" ]]
  [ -f "$output_path" ]
}

@test "cog plan-review save writes user output path" {
  local out="${BATS_TEST_TMPDIR}/review/out.md"

  run cog plan-review save --plan "$PLAN_INPUT" --request "$REQUEST_INPUT" --output "$out"

  assert_success
  assert_output "PLAN_REVIEW_PATH=${out}"
  [ -f "$out" ]
}

@test "cog plan-review orchestrator writes requested output path" {
  local out="${BATS_TEST_TMPDIR}/review/orchestrator.md"

  run cog plan-review orchestrator "$PLAN_INPUT" "$REQUEST_INPUT" "$out"

  assert_success
  assert_output "PLAN_REVIEW_PATH=${out}"
  [ -f "$out" ]
}

@test "cog plan-review validate succeeds for generated artifact" {
  local out="${BATS_TEST_TMPDIR}/review.md"
  run cog plan-review orchestrator "$PLAN_INPUT" "$REQUEST_INPUT" "$out"
  assert_success

  run cog plan-review validate "$out"

  assert_success
  assert_output "PLAN_REVIEW_VALID"
}

@test "cog --json plan-review orchestrator emits schema action and ok" {
  local out="${BATS_TEST_TMPDIR}/review/json.md"

  run cog --json plan-review orchestrator "$PLAN_INPUT" "$REQUEST_INPUT" "$out"

  assert_success
  printf '%s\n' "$output" | jq -e '
    .schema == "cog.plan-review.v1" and .action == "orchestrator" and .ok == true
  ' >/dev/null
}

@test "cog plan-review rejects relative input paths" {
  run --separate-stderr cog plan-review save --plan relative.md --request "$REQUEST_INPUT"

  assert_failure
  [[ $stderr == *"err.kind: InvalidInput"* ]]
}

@test "cog plan-review save rejects a relative --repo-root" {
  run --separate-stderr cog plan-review save \
    --plan "$PLAN_INPUT" --request "$REQUEST_INPUT" --repo-root relative/repo

  assert_failure
  [[ $stderr == *"err.kind: InvalidInput"* ]]
}
