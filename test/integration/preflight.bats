setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  export GIT_FAKE_LOG="${BATS_TEST_TMPDIR}/git-argv.log"
  mkdir -p "$HOME" "$XDG_STATE_HOME" "${BATS_TEST_TMPDIR}/fakebin"
  cat >"${BATS_TEST_TMPDIR}/fakebin/git" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${GIT_FAKE_LOG}"
case "$*" in
  "rev-parse --show-toplevel")
    printf '%s\n' "/tmp/repo"
    ;;
  *)
    exit 2
    ;;
esac
EOF
  cat >"${BATS_TEST_TMPDIR}/fakebin/codex-session" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  version)
    printf '%s\n' "codex-session fake"
    ;;
  *)
    printf '%s\n' "sandbox ok"
    ;;
esac
EOF
  chmod +x "${BATS_TEST_TMPDIR}/fakebin/git" "${BATS_TEST_TMPDIR}/fakebin/codex-session"
  export PATH="${BATS_TEST_TMPDIR}/fakebin:${PATH}"
}

@test "cog preflight codex writes fragment" {
  local out="${BATS_TEST_TMPDIR}/codex.json"

  run cog preflight codex "$out"

  assert_success
  assert_output "RESOLVED $out"
  jq -e '.codex_session.available == true and .codex_session.health == "ok"' "$out" >/dev/null
}

@test "cog preflight git uses fake git" {
  local out="${BATS_TEST_TMPDIR}/git.json"

  run cog preflight git "$out"

  assert_success
  jq -e '.git_root.available == true and .git_root.path == "/tmp/repo"' "$out" >/dev/null
  assert_file_contains "$GIT_FAKE_LOG" "rev-parse --show-toplevel"
}

@test "cog preflight rejects unknown check and supports help" {
  run --separate-stderr cog preflight nope
  assert_failure
  [[ $stderr == *"err.kind: InvalidInput"* ]]

  run cog preflight --help
  assert_success
}

@test "cog preflight claude-env passes when background tasks are disabled" {
  local out="${BATS_TEST_TMPDIR}/claude-env.json"

  run env CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1 \
    BASH_DEFAULT_TIMEOUT_MS=600000 \
    BASH_MAX_TIMEOUT_MS=600000 \
    cog preflight claude-env "$out"

  assert_success
  assert_output "RESOLVED $out"
  jq -e '.claude_env.ok == true
    and .claude_env.advisory == false
    and .claude_env.checks.background_tasks_disabled == true' "$out" >/dev/null
}

@test "cog preflight claude-env fails strict mode when only timeout env is set" {
  local out="${BATS_TEST_TMPDIR}/claude-env-timeouts.json"

  run --separate-stderr env -u CLAUDE_CODE_DISABLE_BACKGROUND_TASKS \
    BASH_DEFAULT_TIMEOUT_MS=600000 \
    BASH_MAX_TIMEOUT_MS=600000 \
    cog preflight claude-env "$out"

  assert_failure
  [[ $stderr == *"err.kind: ClaudeEnvMissing"* ]]
  jq -e '.claude_env.ok == false
    and .claude_env.advisory == false
    and .claude_env.checks.bash_default_timeout_ge_600000 == true
    and .claude_env.checks.bash_max_timeout_ge_600000 == true' "$out" >/dev/null
}
