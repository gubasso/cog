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
    if [ "${GIT_UNBORN:-0}" = 1 ]; then
      exit 1
    fi
    printf '%s\n' "abc1234"
    ;;
  push)
    if [ "${GIT_PUSH_FAIL:-0}" = 1 ]; then
      printf '%s\n' "non-fast-forward"
      exit 1
    fi
    printf '%s\n' "pushed"
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

@test "cog gc-push pushes successfully" {
  run cog gc-push --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .sha == "abc1234" and .failure_class == null' >/dev/null
}

@test "cog gc-push targets repo-root with git -C" {
  local repo="${BATS_TEST_TMPDIR}/target-repo"
  mkdir -p "$repo"

  run cog gc-push --repo-root "$repo" --json

  assert_success
  assert_file_contains "$GIT_FAKE_LOG" ".*-C $repo rev-parse --short HEAD"
  assert_file_contains "$GIT_FAKE_LOG" ".*-C $repo push"
}

@test "cog gc-push rejects invalid repo-root" {
  run --separate-stderr cog gc-push --repo-root "${BATS_TEST_TMPDIR}/missing" --json

  assert_failure
  [[ $stderr == *"gc-push: not a git worktree"* ]]
}

@test "cog gc-push classifies failed pushes" {
  export GIT_PUSH_FAIL=1

  run cog gc-push --json

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and .failure_class == "push-non-hook"' >/dev/null
}

@test "cog gc-push rejects extra args" {
  run --separate-stderr cog gc-push one two

  assert_failure
  [[ $stderr == *"err.kind: TooManyArguments"* ]]
}

@test "cog --json gc-push honors the global JSON flag" {
  run cog --json gc-push

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .sha == "abc1234"' >/dev/null
}

@test "cog gc-push --help dispatches" {
  run cog gc-push --help

  assert_success
  [[ $output == *"Run git push"* ]]
}
