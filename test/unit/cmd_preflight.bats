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
  source "${LIB_DIR}/functions/fn_refs.sh"
  source "${LIB_DIR}/functions/fn_git.sh"
  source "${LIB_DIR}/functions/fn_codex.sh"
  source "${LIB_DIR}/commands/cmd_preflight.sh"
}

@test "preflight JSON array helper encodes lines" {
  run __cog_preflight_json_array_from_lines one two

  assert_success
  printf '%s\n' "$output" | jq -e '. == ["one","two"]' >/dev/null
}

@test "preflight cache path is empty without session" {
  unset CLAUDE_CODE_SESSION_ID

  run __cog_preflight_agents_cache_path

  assert_success
  assert_output ""
}

@test "preflight rejects unknown agents option" {
  run --separate-stderr __cog_preflight_agents --bad

  assert_failure 65
  [[ $stderr == *"err.kind: InvalidInput"* ]]
}

@test "preflight claude-env passes when background tasks are disabled" {
  local out="${BATS_TEST_TMPDIR}/claude-env.json"
  # shellcheck disable=SC2030 # Each bats @test runs in its own subshell; exporting the env here is intentional.
  export CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1
  unset BASH_DEFAULT_TIMEOUT_MS BASH_MAX_TIMEOUT_MS CLAUDE_AUTO_BACKGROUND_TASKS

  run __cog_preflight_claude_env "$out"

  assert_success
  jq -e '.claude_env.ok == true and .claude_env.advisory == false' "$out" >/dev/null
}

@test "preflight claude-env fails strict mode when only timeout env is set" {
  local out="${BATS_TEST_TMPDIR}/claude-env-timeouts.json"
  unset CLAUDE_CODE_DISABLE_BACKGROUND_TASKS CLAUDE_AUTO_BACKGROUND_TASKS
  export BASH_DEFAULT_TIMEOUT_MS=600000
  export BASH_MAX_TIMEOUT_MS=600000

  run --separate-stderr __cog_preflight_claude_env "$out"

  assert_failure 70
  [[ $stderr == *"err.kind: ClaudeEnvMissing"* ]]
  jq -e '.claude_env.ok == false
    and .claude_env.checks.background_tasks_disabled == false
    and .claude_env.checks.bash_default_timeout_ge_600000 == true
    and .claude_env.checks.bash_max_timeout_ge_600000 == true' "$out" >/dev/null
}

@test "preflight claude-env advisory mode records absent env without failing" {
  local out="${BATS_TEST_TMPDIR}/claude-env-advisory.json"
  unset CLAUDE_CODE_DISABLE_BACKGROUND_TASKS BASH_DEFAULT_TIMEOUT_MS BASH_MAX_TIMEOUT_MS CLAUDE_AUTO_BACKGROUND_TASKS

  run __cog_preflight_claude_env "$out" --allow-legacy-session

  assert_success
  [[ $output == *"WARNING claude-env preflight advisory"* ]]
  jq -e '.claude_env.ok == false and .claude_env.advisory == true' "$out" >/dev/null
}

@test "preflight claude-env fails closed for an explicit wrong value even with --allow-legacy-session" {
  local out="${BATS_TEST_TMPDIR}/claude-env-explicit-zero.json"
  # shellcheck disable=SC2030,SC2031 # Each bats @test runs in its own subshell; exporting the env here is intentional.
  export CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=0
  unset BASH_DEFAULT_TIMEOUT_MS BASH_MAX_TIMEOUT_MS CLAUDE_AUTO_BACKGROUND_TASKS

  run --separate-stderr __cog_preflight_claude_env "$out" --allow-legacy-session

  assert_failure 70
  [[ $stderr == *"err.kind: ClaudeEnvMissing"* ]]
  jq -e '.claude_env.ok == false and .claude_env.advisory == false' "$out" >/dev/null
}
