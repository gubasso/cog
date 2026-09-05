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
  source "${LIB_DIR}/functions/fn_env.sh"
  source "${LIB_DIR}/commands/cmd_gc_push.sh"
}

@test "gc-push log file uses cog skill-runs path" {
  run __cog_gc_push_new_log_file "$(__cog_gc_push_log_dir)"

  assert_success
  [[ $output == "${XDG_STATE_HOME}/cog/skill-runs/push-"* ]]
}

@test "gc-push rejects missing output mode" {
  run --separate-stderr cog::cmd::gc_push

  assert_failure 64
  [[ $stderr == *"err.kind: MissingArgument"* ]]
}

@test "gc-push rejects duplicate output mode" {
  run --separate-stderr cog::cmd::gc_push --json out.json

  assert_failure 64
  [[ $stderr == *"err.kind: TooManyArguments"* ]]
}

@test "gc-push with COG_ENV_RUNNER=bare pushes to a remote (non-nix regression)" {
  local remote="${BATS_TEST_TMPDIR}/remote.git" repo="${BATS_TEST_TMPDIR}/repo"
  git init -q --bare "$remote"
  git init -q "$repo"
  git -C "$repo" config user.email t@t.co
  git -C "$repo" config user.name t
  printf 'hello\n' >"$repo/file.txt"
  git -C "$repo" add file.txt
  git -C "$repo" commit -q -m 'test: add file'
  git -C "$repo" remote add origin "$remote"
  git -C "$repo" push -q -u origin HEAD >/dev/null 2>&1

  COG_ENV_RUNNER=bare run cog::cmd::gc_push --repo-root "$repo" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true' >/dev/null
}

@test "gc-push log dir ignores XDG_RUNTIME_DIR" {
  export XDG_RUNTIME_DIR="${BATS_TEST_TMPDIR}/runtime"
  mkdir -p "$XDG_RUNTIME_DIR"

  run __cog_gc_push_log_dir

  assert_success
  assert_output "${XDG_STATE_HOME}/cog/skill-runs"
}
