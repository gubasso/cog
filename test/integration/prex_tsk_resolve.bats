setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  mkdir -p "${BATS_TEST_TMPDIR}/run" "${BATS_TEST_TMPDIR}/fakebin"
  cat >"${BATS_TEST_TMPDIR}/fakebin/tsk" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  id)
    printf '%s\n' "BRANCH-7"
    ;;
  show)
    if [ "${TSK_SHOW_FAIL:-0}" = 1 ]; then
      printf '%s\n' "show failed" >&2
      exit 1
    fi
    printf 'issue body for %s\n' "$2"
    ;;
  *)
    exit 2
    ;;
esac
EOF
  chmod +x "${BATS_TEST_TMPDIR}/fakebin/tsk"
  export PATH="${BATS_TEST_TMPDIR}/fakebin:${PATH}"
}

@test "cog prex-tsk-resolve resolves explicit and stored ids" {
  run cog prex-tsk-resolve --run-dir "${BATS_TEST_TMPDIR}/run" --id ISSUE-2 --json

  assert_success
  printf '%s\n' "$output" | jq -e '.tsk_id == "ISSUE-2"' >/dev/null
  assert_file_contains "${BATS_TEST_TMPDIR}/run/tsk-issue.md" "issue body for ISSUE-2"

  printf '%s\n' "1:STORED-3" >"${BATS_TEST_TMPDIR}/run/tsk-impl"
  run cog prex-tsk-resolve --run-dir "${BATS_TEST_TMPDIR}/run" --json
  assert_success
  printf '%s\n' "$output" | jq -e '.tsk_id == "STORED-3"' >/dev/null
}

@test "cog executor-prex-tsk-resolve resolves explicit id" {
  mkdir -p "${BATS_TEST_TMPDIR}/run-new"

  run cog executor-prex-tsk-resolve --run-dir "${BATS_TEST_TMPDIR}/run-new" --id ISSUE-4 --json

  assert_success
  printf '%s\n' "$output" | jq -e '.tsk_id == "ISSUE-4"' >/dev/null
  assert_file_contains "${BATS_TEST_TMPDIR}/run-new/tsk-issue.md" "issue body for ISSUE-4"
}

@test "cog prex-tsk-resolve writes stderr on tsk show failure" {
  export TSK_SHOW_FAIL=1

  run --separate-stderr cog prex-tsk-resolve --run-dir "${BATS_TEST_TMPDIR}/run" --id BAD-1 --json

  assert_failure
  assert_file_contains "${BATS_TEST_TMPDIR}/run/tsk-issue.err" "show failed"
}

@test "cog prex-tsk-resolve --help dispatches" {
  run cog prex-tsk-resolve --help

  assert_success
  [[ $output == *"Resolve a tsk issue"* ]]
}

@test "cog executor-prex-tsk-resolve --help dispatches" {
  run cog executor-prex-tsk-resolve --help

  assert_success
  [[ $output == *"executor-prex"* ]]
}
