setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  export GIT_FAKE_LOG="${BATS_TEST_TMPDIR}/git-argv.log"
  export GIT_STAGE_FINAL="${GIT_STAGE_FINAL:-session.txt}"
  mkdir -p "$HOME" "$XDG_STATE_HOME" "${BATS_TEST_TMPDIR}/fakebin"
  cat >"${BATS_TEST_TMPDIR}/fakebin/git" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${GIT_FAKE_LOG}"
case "$*" in
  "rev-parse --show-toplevel")
    printf '%s\n' "/tmp/repo"
    ;;
  "diff --staged --name-only")
    count="$(grep -c '^diff --staged --name-only$' "${GIT_FAKE_LOG}" 2>/dev/null || true)"
    if [ "$count" -eq 1 ]; then
      printf '%s\n' "old.txt"
    elif [ "$count" -eq 2 ]; then
      :
    else
      printf '%s\n' "${GIT_STAGE_FINAL}"
    fi
    ;;
  reset\ HEAD\ --*)
    ;;
  add\ --*)
    ;;
  *)
    printf 'unexpected git args: %s\n' "$*" >&2
    exit 2
    ;;
esac
EOF
  chmod +x "${BATS_TEST_TMPDIR}/fakebin/git"
  export PATH="${BATS_TEST_TMPDIR}/fakebin:${PATH}"
}

@test "cog gc-stage reconciles staged files" {
  local session="${BATS_TEST_TMPDIR}/session.txt"
  printf '%s\n' session.txt >"$session"

  run cog gc-stage --session-files "$session" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .unstaged == ["old.txt"] and .staged == ["session.txt"]' >/dev/null
  assert_file_contains "$GIT_FAKE_LOG" "reset HEAD -- old.txt"
  assert_file_contains "$GIT_FAKE_LOG" "add -- session.txt"
}

@test "cog gc-stage reports mismatch after emitting JSON" {
  export GIT_STAGE_FINAL="other.txt"
  local session="${BATS_TEST_TMPDIR}/session.txt"
  printf '%s\n' session.txt >"$session"

  run cog gc-stage --session-files "$session" --json

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and (.mismatch | length > 0)' >/dev/null
}

@test "cog gc-stage rejects absolute session paths" {
  local session="${BATS_TEST_TMPDIR}/session.txt"
  printf '%s\n' /abs/path >"$session"

  run --separate-stderr cog gc-stage --session-files "$session" --json

  assert_failure
  [[ $stderr == *"err.kind: InvalidInput"* ]]
}

@test "cog --json gc-stage honors the global JSON flag" {
  local session="${BATS_TEST_TMPDIR}/session.txt"
  printf '%s\n' session.txt >"$session"

  run cog --json gc-stage --session-files "$session"

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .staged == ["session.txt"]' >/dev/null
}

@test "cog gc-stage --help dispatches" {
  run cog gc-stage --help

  assert_success
  [[ $output == *"Reconcile and stage"* ]]
}
