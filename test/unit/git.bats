setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export LIB_DIR="${BATS_TEST_DIRNAME}/../../lib"
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
  -C\ */worktree\ rev-parse\ --show-toplevel)
    printf '%s\n' "/tmp/repo-for"
    ;;
  "branch --show-current")
    printf '%s\n' "main"
    ;;
  "status --porcelain=v1 -uall")
    printf '%s\n' "M  staged.txt" " M unstaged.txt" "?? untracked dir/file.txt" "R  old name.txt -> new name.txt"
    ;;
  "diff --staged --name-only")
    printf '%s\n' "staged one.txt" "staged-two.sh"
    ;;
  "diff --name-only")
    printf '%s\n' "unstaged one.txt"
    ;;
  "diff --staged --numstat")
    printf '1\t2\tstaged.txt\n-\t-\tbinary.bin\n'
    ;;
  "diff --numstat")
    printf '3\t4\tunstaged.txt\n'
    ;;
  log*)
    printf 'abc123\tfirst subject\n'
    printf 'def456\tsecond subject\n'
    ;;
  *)
    printf 'unexpected git args: %s\n' "$*" >&2
    exit 2
    ;;
esac
EOF
  chmod +x "${BATS_TEST_TMPDIR}/fakebin/git"
  export PATH="${BATS_TEST_TMPDIR}/fakebin:${PATH}"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/helpers.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_ui_print.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_log.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_error_raise.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_json_write.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_git.sh"
}

@test "git_status_porcelain uses porcelain v1 and -uall" {
  run cog::fn::git_status_porcelain

  assert_success
  assert_line "?? untracked dir/file.txt"
  assert_file_contains "$GIT_FAKE_LOG" "status --porcelain=v1 -uall"
}

@test "git_root_for resolves arbitrary worktree and returns false for missing dir" {
  mkdir -p "${BATS_TEST_TMPDIR}/worktree"

  run cog::fn::git_root_for "${BATS_TEST_TMPDIR}/worktree"

  assert_success
  assert_output "/tmp/repo-for"

  run cog::fn::git_root_for "${BATS_TEST_TMPDIR}/missing"

  assert_failure
  assert_output ""
}

@test "git_status_json maps staged unstaged untracked and rename entries" {
  run cog::fn::git_status_json

  assert_success
  printf '%s\n' "$output" | jq -e '
    .root == "/tmp/repo" and
    .branch == "main" and
    (.files[] | select(.path == "staged.txt" and .staged == true and .unstaged == false)) and
    (.files[] | select(.path == "unstaged.txt" and .staged == false and .unstaged == true)) and
    (.files[] | select(.path == "untracked dir/file.txt" and .untracked == true)) and
    (.files[] | select(.path == "new name.txt" and .orig_path == "old name.txt"))
  ' >/dev/null
}

@test "git file list JSON preserves filenames with spaces" {
  run cog::fn::git_staged_files_json

  assert_success
  printf '%s\n' "$output" | jq -e '.[0] == "staged one.txt" and .[1] == "staged-two.sh"' >/dev/null

  run cog::fn::git_unstaged_files_json
  assert_success
  printf '%s\n' "$output" | jq -e '.[0] == "unstaged one.txt"' >/dev/null
}

@test "git_diff_stat_json maps binary counts to zero and rejects bad mode" {
  run cog::fn::git_diff_stat_json --staged

  assert_success
  printf '%s\n' "$output" | jq -e '.mode == "staged" and (.files[] | select(.path == "binary.bin" and .added == 0 and .deleted == 0))' >/dev/null

  run --separate-stderr cog::fn::git_diff_stat_json --bad
  assert_failure 64
  [[ $stderr == *"err.kind: InvalidInput"* ]]
}

@test "git_recent_log_json rejects nonnumeric limit" {
  run --separate-stderr cog::fn::git_recent_log_json nope

  assert_failure 64
  [[ $stderr == *"err.kind: InvalidInput"* ]]
}

@test "git_classify_failure_log covers confirmed classes" {
  local log="${BATS_TEST_TMPDIR}/failure.log"
  local cases=(
    "setup-missing|Author identity unknown"
    "push-setup-missing|has no upstream branch"
    "auto-fixer|shfmt wrote file"
    "commit-message|commit message"
    "content-fix|shellcheck SC2086"
    "push-hook|pre-push hook id: pre-push"
    "push-non-hook|non-fast-forward"
    "stuck|ANALYSIS GATE STUCK"
    "unknown|plain failure"
  )
  local item expected body

  for item in "${cases[@]}"; do
    expected="${item%%|*}"
    body="${item#*|}"
    printf '%s\n' "$body" >"$log"
    run cog::fn::git_classify_failure_log "$log"
    assert_success
    printf '%s\n' "$output" | jq -e --arg expected "$expected" '.class == $expected' >/dev/null
  done
}

@test "git_classify_failure_log rejects unreadable log" {
  run --separate-stderr cog::fn::git_classify_failure_log "${BATS_TEST_TMPDIR}/missing.log"

  assert_failure 66
  [[ $stderr == *"err.kind: InputUnreadable"* ]]
}
