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
