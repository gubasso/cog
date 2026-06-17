setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_DATA_HOME="${BATS_TEST_TMPDIR}/data"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  unset RUN_DIR DOCS_NOTES_REPO REFACTOR_GUIDELINE RIPTASK_REPO
  mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "${BATS_TEST_TMPDIR}/fakebin"
  export TSK_LOG="${BATS_TEST_TMPDIR}/tsk-argv.log"
  cat >"${BATS_TEST_TMPDIR}/fakebin/tsk" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$TSK_LOG"
case "$1" in
  show)
    printf 'issue body for %s\n' "$2"
    ;;
  path)
    printf '/tmp/tasks/%s.md\n' "$2"
    ;;
  new)
    printf 'tsk-999\nhttps://example.invalid/tsk-999\n'
    ;;
  *)
    exit 2
    ;;
esac
EOF
  cat >"${BATS_TEST_TMPDIR}/fakebin/gh" <<'EOF'
#!/usr/bin/env bash
printf 'network tool must not run\n' >&2
exit 9
EOF
  chmod +x "${BATS_TEST_TMPDIR}/fakebin/tsk" "${BATS_TEST_TMPDIR}/fakebin/gh"
  export PATH="${BATS_TEST_TMPDIR}/fakebin:$PATH"
}

@test "cog tsk-fetch-issue fetches existing issue" {
  run cog tsk-fetch-issue --id tsk-123 --json

  assert_success
  printf '%s\n' "$output" | jq -e '.mode == "fetch" and .id == "tsk-123" and .path == "/tmp/tasks/tsk-123.md"' >/dev/null
  assert_file_contains "$TSK_LOG" "show tsk-123"
  assert_file_not_contains "$TSK_LOG" "gh"
}

@test "cog tsk-fetch-issue creates an issue" {
  printf 'body text\n' >"${BATS_TEST_TMPDIR}/body.md"

  run cog tsk-fetch-issue --title "New task" --body-file "${BATS_TEST_TMPDIR}/body.md" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.mode == "create" and .id == "tsk-999" and .remote_url == "https://example.invalid/tsk-999"' >/dev/null
  assert_file_contains "$TSK_LOG" "new -t New task -d body text"
}

@test "cog tsk-fetch-issue --help dispatches" {
  run cog tsk-fetch-issue --help

  assert_success
  [[ $output == *"Fetch or create a tsk issue"* ]]
}
