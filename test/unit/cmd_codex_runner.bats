setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export LIB_DIR="${BATS_TEST_DIRNAME}/../../lib"
  source "${LIB_DIR}/helpers.sh"
  source "${LIB_DIR}/functions/fn_ui_print.sh"
  source "${LIB_DIR}/functions/fn_log.sh"
  source "${LIB_DIR}/functions/fn_error_raise.sh"
  source "${LIB_DIR}/functions/fn_json_write.sh"
  source "${LIB_DIR}/functions/fn_codex.sh"
  source "${LIB_DIR}/functions/fn_rundir.sh"
  source "${LIB_DIR}/commands/cmd_codex_runner.sh"
}

@test "codex-runner bool helper only marks ok true" {
  run __cog_codex_runner_bool_for_status ok
  assert_success
  assert_output true

  run __cog_codex_runner_bool_for_status nonzero
  assert_success
  assert_output false
}

@test "codex-runner verify proof JSON succeeds with artifact" {
  local proof="${BATS_TEST_TMPDIR}/proof.diff"
  local artifact="${BATS_TEST_TMPDIR}/artifact.json"
  printf '%s\n' diff >"$proof"
  printf '%s\n' '{"ok":true}' >"$artifact"

  run __cog_codex_runner_verify_proof_json --proof "$proof" --artifact "$artifact" --require-json '.ok == true'

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and (.artifacts | length) == 1' >/dev/null
}

@test "codex-runner verify proof JSON reports missing artifact" {
  local proof="${BATS_TEST_TMPDIR}/proof.diff"
  printf '%s\n' diff >"$proof"

  run __cog_codex_runner_verify_proof_json --proof "$proof" --artifact "${BATS_TEST_TMPDIR}/missing"

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == false and (.reason | contains("missing or empty artifact"))' >/dev/null
}

@test "codex-runner orientation command emits preamble and rejects invalid mode" {
  run cog::cmd::codex_runner orientation read-only
  assert_success
  [[ -n $output ]]
  [[ $output == *"STRICT READ-ONLY MODE"* ]]

  run cog::cmd::codex_runner orientation nope
  assert_failure
}

@test "codex-runner explain-status command emits guidance and rejects unknown status" {
  run cog::cmd::codex_runner explain-status quota-75
  assert_success
  [[ -n $output ]]

  run cog::cmd::codex_runner explain-status nope
  assert_failure
}

@test "codex-runner require-abs rejects a relative artifact path" {
  run --separate-stderr __cog_codex_runner_require_abs --state codex-state.json
  assert_failure
  [[ $stderr == *"must be absolute"* ]]

  run --separate-stderr __cog_codex_runner_require_abs --output "./codex-out.txt"
  assert_failure
  [[ $stderr == *"must be absolute"* ]]
}

@test "codex-runner require-abs accepts an absolute artifact path" {
  run __cog_codex_runner_require_abs --state /run/dir/codex.longrun.json
  assert_success
}

@test "codex-runner output-collision guard fails when a prompt --output equals the runner --output" {
  local prompt="${BATS_TEST_TMPDIR}/prompt.md"
  local out="${BATS_TEST_TMPDIR}/prepared-plan.md"
  # shellcheck disable=SC2016 # literal $plan-oneshot in the prompt body, not an expansion
  printf 'Run $plan-oneshot --output %s to save the plan.\n' "$out" >"$prompt"

  run --separate-stderr __cog_codex_runner_guard_output_collision "$out" "$prompt"

  assert_failure
  [[ $stderr == *"collides"* ]]
  [[ $stderr == *"codex-output"* ]]
}

@test "codex-runner output-collision guard passes when the runner --output is distinct" {
  local prompt="${BATS_TEST_TMPDIR}/prompt.md"
  # shellcheck disable=SC2016 # literal $plan-oneshot in the prompt body, not an expansion
  printf 'Run $plan-oneshot --output %s/prepared-plan.md to save the plan.\n' "$BATS_TEST_TMPDIR" >"$prompt"

  run __cog_codex_runner_guard_output_collision "${BATS_TEST_TMPDIR}/prepare-codex-output.md" "$prompt"

  assert_success
}

@test "codex-runner output-collision guard ignores angle-bracket placeholder prompt targets" {
  local prompt="${BATS_TEST_TMPDIR}/prompt.md"
  printf 'Save via --output <RUN_DIR>/prepared-plan.md as the plan.\n' >"$prompt"

  run __cog_codex_runner_guard_output_collision "/run/dir/prepared-plan.md" "$prompt"

  assert_success
}

@test "codex-runner output-collision guard catches a backslash-continued prompt --output" {
  local prompt="${BATS_TEST_TMPDIR}/prompt.md"
  local out="${BATS_TEST_TMPDIR}/prepared-plan.md"
  printf 'cog plan-doc save \\\n  --output %s\n' "$out" >"$prompt"

  run --separate-stderr __cog_codex_runner_guard_output_collision "$out" "$prompt"

  assert_failure
  [[ $stderr == *"collides"* ]]
}

@test "codex-runner output-collision guard ignores an unrelated prompt --output" {
  local prompt="${BATS_TEST_TMPDIR}/prompt.md"
  printf 'See the prior run at --output /some/other/path.md for reference.\n' >"$prompt"

  run __cog_codex_runner_guard_output_collision "${BATS_TEST_TMPDIR}/prepared-plan.md" "$prompt"

  assert_success
}

@test "codex-runner output-collision guard defers on an unreadable prompt" {
  run __cog_codex_runner_guard_output_collision "/run/dir/out.md" "${BATS_TEST_TMPDIR}/missing.md"

  assert_success
}
