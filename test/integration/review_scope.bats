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
    [ "${GIT_ROOT_FAIL:-0}" = 1 ] && exit 1
    printf '%s\n' "/tmp/repo"
    ;;
  "branch --show-current")
    printf '%s\n' "main"
    ;;
  "diff --staged --name-only")
    printf '%s\n' "staged.txt"
    ;;
  "diff --name-only")
    printf '%s\n' "unstaged.txt"
    ;;
  "status --porcelain=v1 -uall")
    printf '%s\n' "M  staged.txt" " M unstaged.txt" "?? new.txt"
    ;;
  "diff --staged --numstat")
    printf '1\t0\tstaged.txt\n'
    ;;
  "diff --numstat")
    printf '2\t1\tunstaged.txt\n'
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

@test "cog review-scope emits changed file union" {
  run cog review-scope --json

  assert_success
  printf '%s\n' "$output" | jq -e '.changed_files == ["new.txt","staged.txt","unstaged.txt"]' >/dev/null
}

@test "cog review-scope surfaces git failures" {
  export GIT_ROOT_FAIL=1

  run --separate-stderr cog review-scope --json

  assert_failure
  [[ $stderr == *"err.kind:"* ]]
}

@test "cog review-scope writes fragments" {
  local out="${BATS_TEST_TMPDIR}/scope.json"

  run cog review-scope "$out"

  assert_success
  assert_output "RESOLVED $out"
  jq -e '.repo_root == "/tmp/repo"' "$out" >/dev/null
}

@test "cog review-scope --help dispatches" {
  run cog review-scope --help

  assert_success
  [[ $output == *"Detect changed-file"* ]]
}
