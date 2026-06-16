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
  source "${LIB_DIR}/functions/fn_git.sh"
  source "${LIB_DIR}/commands/cmd_gc_commit.sh"
}

@test "gc-commit path parser dedupes valid paths" {
  local file="${BATS_TEST_TMPDIR}/paths.txt"
  printf '%s\n' a.txt a.txt >"$file"
  local -a paths=()

  __cog_gc_commit_read_paths paths "$file"

  [ "${#paths[@]}" -eq 1 ]
}

@test "gc-commit log file uses cog skill-runs path" {
  run __cog_gc_commit_new_log_file "$(__cog_gc_commit_log_dir)"

  assert_success
  [[ $output == "${XDG_STATE_HOME}/cog/skill-runs/commit-hook-"* ]]
}

@test "gc-commit requires paths file" {
  run --separate-stderr cog::cmd::gc_commit --message-file missing --json

  assert_failure 64
  [[ $stderr == *"err.kind: MissingArgument"* ]]
}
