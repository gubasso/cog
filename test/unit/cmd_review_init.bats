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
  source "${LIB_DIR}/commands/cmd_review_init.sh"
}

@test "review-init path JSON includes expected keys" {
  run __cog_review_init_paths_json /tmp/run /tmp/run/paths.env

  assert_success
  printf '%s\n' "$output" | jq -e '
    .paths.tech_scope == "/tmp/run/tech-scope.json"
    and (.paths.classification | not)
    and (.paths.cli_signals | not)
    and (.paths.refs | not)
  ' >/dev/null
}

@test "review-init writes sourceable paths env" {
  local run_dir="${BATS_TEST_TMPDIR}/run with space"
  mkdir -p "$run_dir"

  run __cog_review_init_write_paths_env "$run_dir" "${run_dir}/paths.env"

  assert_success
  assert_file_contains "${run_dir}/paths.env" "RUN_DIR="
  assert_file_contains "${run_dir}/paths.env" "TECH_SCOPE_JSON="
  refute grep -q "CLASSIFICATION_JSON=" "${run_dir}/paths.env"
  refute grep -q "CLI_JSON=" "${run_dir}/paths.env"
  refute grep -q "REFS_JSON=" "${run_dir}/paths.env"
}

@test "review-init rejects missing prefix" {
  run --separate-stderr cog::cmd::review_init

  assert_failure 64
  [[ $stderr == *"err.kind: MissingArgument"* ]]
}
