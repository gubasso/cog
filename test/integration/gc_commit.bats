setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  export XDG_RUNTIME_DIR="${BATS_TEST_TMPDIR}/runtime"
  export GIT_FAKE_LOG="${BATS_TEST_TMPDIR}/git-argv.log"
  mkdir -p "$HOME" "$XDG_STATE_HOME" "$XDG_RUNTIME_DIR" "${BATS_TEST_TMPDIR}/fakebin"
  cat >"${BATS_TEST_TMPDIR}/fakebin/git" <<'EOF'
#!/usr/bin/env bash
git_root="/tmp/repo"
if [ "$1" = "-C" ]; then
  git_root="$2"
  printf '%s\n' "$*" >>"${GIT_FAKE_LOG}"
  shift 2
else
  printf '%s\n' "$*" >>"${GIT_FAKE_LOG}"
fi
case "$*" in
  "rev-parse --show-toplevel")
    printf '%s\n' "$git_root"
    ;;
  "rev-parse --short HEAD")
    printf '%s\n' "abc1234"
    ;;
  commit*)
    if [ "${GIT_COMMIT_FAIL:-0}" = 1 ]; then
      printf '%s\n' "shellcheck SC2086"
      exit 1
    fi
    printf '%s\n' "committed"
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

make_inputs() {
  printf '%s\n' "subject" >"${BATS_TEST_TMPDIR}/message.txt"
  printf '%s\n' "file one.txt" >"${BATS_TEST_TMPDIR}/paths.txt"
}

@test "cog gc-commit commits explicit paths" {
  make_inputs

  run cog gc-commit --message-file "${BATS_TEST_TMPDIR}/message.txt" --paths-file "${BATS_TEST_TMPDIR}/paths.txt" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .sha == "abc1234" and .paths == ["file one.txt"]' >/dev/null
  assert_file_contains "$GIT_FAKE_LOG" "commit -F - -- file one.txt"
}

@test "cog gc-commit targets repo-root with git -C" {
  local repo="${BATS_TEST_TMPDIR}/target-repo"
  mkdir -p "$repo"
  make_inputs

  run cog gc-commit --message-file "${BATS_TEST_TMPDIR}/message.txt" --paths-file "${BATS_TEST_TMPDIR}/paths.txt" --repo-root "$repo" --json

  assert_success
  assert_file_contains "$GIT_FAKE_LOG" ".*-C $repo commit -F - -- file one.txt"
  assert_file_contains "$GIT_FAKE_LOG" ".*-C $repo rev-parse --short HEAD"
}

@test "cog gc-commit rejects invalid repo-root" {
  make_inputs

  run --separate-stderr cog gc-commit --message-file "${BATS_TEST_TMPDIR}/message.txt" --paths-file "${BATS_TEST_TMPDIR}/paths.txt" --repo-root "${BATS_TEST_TMPDIR}/missing" --json

  assert_failure
  [[ $stderr == *"gc-commit: not a git worktree"* ]]
}

@test "cog gc-commit emits failure JSON and exits nonzero" {
  export GIT_COMMIT_FAIL=1
  make_inputs

  run cog gc-commit --message-file "${BATS_TEST_TMPDIR}/message.txt" --paths-file "${BATS_TEST_TMPDIR}/paths.txt" --json

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and .sha == null and .exit_code == 1' >/dev/null
}

@test "cog gc-commit rejects missing message file" {
  printf '%s\n' file.txt >"${BATS_TEST_TMPDIR}/paths.txt"

  run --separate-stderr cog gc-commit --message-file "${BATS_TEST_TMPDIR}/missing.txt" --paths-file "${BATS_TEST_TMPDIR}/paths.txt" --json

  assert_failure
  [[ $stderr == *"err.kind: InputUnreadable"* ]]
}

@test "cog gc-commit --help dispatches" {
  run cog gc-commit --help

  assert_success
  [[ $output == *"Commit with a message file"* ]]
}
