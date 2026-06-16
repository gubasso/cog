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
  source "${LIB_DIR}/commands/cmd_review_cli_signals.sh"
}

@test "review-cli-signals projection counts signals" {
  local classification='{"git_root":"/tmp/repo","is_cli":true,"cli_signals":["a","b"],"project_types":["cli"],"languages":[],"frameworks":[]}'

  run __cog_review_cli_signals_build_json "$classification"

  assert_success
  printf '%s\n' "$output" | jq -e '.signal_count == 2 and .is_cli == true' >/dev/null
}

@test "review-cli-signals requires classification" {
  run --separate-stderr cog::cmd::review_cli_signals --json

  assert_failure 70
  [[ $stderr == *"err.kind: MissingClassification"* ]]
}

@test "review-cli-signals rejects duplicate output mode" {
  run --separate-stderr cog::cmd::review_cli_signals --classification x --json out

  assert_failure 64
  [[ $stderr == *"err.kind: TooManyArguments"* ]]
}
