setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_DATA_HOME="${BATS_TEST_TMPDIR}/data"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  unset RUN_DIR DOCS_NOTES_REPO REFACTOR_GUIDELINE RIPTASK_REPO
  mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "${BATS_TEST_TMPDIR}/fakebin"
  cat >"${BATS_TEST_TMPDIR}/fakebin/git" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  "rev-parse --show-toplevel") printf '%s\n' "/tmp/repo" ;;
  "branch --show-current") printf '%s\n' "main" ;;
  "status --porcelain=v1 -uall") printf '%s\n' "M  staged.txt" " M unstaged.txt" "?? new.txt" ;;
  "diff --staged --name-only") printf '%s\n' "staged.txt" ;;
  "diff --name-only") printf '%s\n' "unstaged.txt" ;;
  "diff --staged --numstat") printf '1\t0\tstaged.txt\n' ;;
  "diff --numstat") printf '2\t1\tunstaged.txt\n' ;;
  log*) printf 'abc123\tinitial\n' ;;
  *) printf 'unexpected git args: %s\n' "$*" >&2; exit 2 ;;
esac
EOF
  chmod +x "${BATS_TEST_TMPDIR}/fakebin/git"
  export PATH="${BATS_TEST_TMPDIR}/fakebin:$PATH"
}

@test "cog tsk-snapshot emits git snapshot" {
  run cog tsk-snapshot --json

  assert_success
  printf '%s\n' "$output" | jq -e '.repo_root == "/tmp/repo" and .branch == "main" and (.recent_log | length == 1)' >/dev/null
}

@test "cog tsk-snapshot --help dispatches" {
  run cog tsk-snapshot --help

  assert_success
  [[ $output == *"Capture read-only git context"* ]]
}
