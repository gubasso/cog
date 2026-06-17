setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  export PYTEST_FAKE_LOG="${BATS_TEST_TMPDIR}/pytest-argv.log"
  export YQ_FAKE_LOG="${BATS_TEST_TMPDIR}/yq-argv.log"
  mkdir -p "$HOME" "$XDG_STATE_HOME" "${BATS_TEST_TMPDIR}/fakebin"
  cat >"${BATS_TEST_TMPDIR}/fakebin/pytest" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$PYTEST_FAKE_LOG"
if [[ $* == "--help" ]]; then
  printf '%s\n' "usage: pytest [-n auto]"
  exit 0
fi
exit 0
EOF
  cat >"${BATS_TEST_TMPDIR}/fakebin/yq" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$YQ_FAKE_LOG"
case "$*" in
  "e . "*|"e '.' "*) exit 0 ;;
  "e -o=json .phase // null "*) printf '%s\n' '"4-in-progress"' ;;
  "e -o=json .[\"implementation-log\"] // [] "*) printf '%s\n' '[{"status":"needs-replan","rolled-back":true}]' ;;
  *) printf '%s\n' 'null' ;;
esac
EOF
  chmod +x "${BATS_TEST_TMPDIR}/fakebin/pytest" "${BATS_TEST_TMPDIR}/fakebin/yq"
  export PATH="${BATS_TEST_TMPDIR}/fakebin:${PATH}"
}

@test "cog test-review-discover selects pytest-xdist and parses batch status" {
  local repo="${BATS_TEST_TMPDIR}/pyrepo"
  mkdir -p "$repo/tests" "$repo/.test-review"
  touch "$repo/pyproject.toml" "$repo/tests/test_app.py" "$repo/.test-review/MANIFEST.yaml"
  cat >"$repo/.test-review/REFACTOR_PLAN.md" <<'EOF'
File: tests/test_app.py
- [ ] T-PY-001 fix app test
- [x] T-PY-002 done task
File: tests/test_other.py
- [ ] T-PY-003 other task
EOF

  run cog test-review-discover --repo-root "$repo" --json

  assert_success
  printf '%s\n' "$output" | jq -e '
    .runner.name == "pytest-xdist" and
    .runner.command == ["pytest","-n","auto"] and
    (.project.languages | index("python")) and
    .batch_status.task_count == 3 and
    .batch_status.pending_task_count == 2 and
    .batch_status.next_batch.task_ids == ["T-PY-001"]
  ' >/dev/null
  assert_file_contains "$PYTEST_FAKE_LOG" "--help"
}

@test "cog test-review-discover prefers make test before bats" {
  local repo="${BATS_TEST_TMPDIR}/makerepo"
  mkdir -p "$repo/tests"
  printf '%s\n' "test:" >"$repo/Makefile"
  touch "$repo/tests/test_cli.bats"

  run cog test-review-discover --repo-root "$repo" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.runner.name == "make-test" and .runner.command == ["make","test"] and (.runner.candidates[] | select(.name == "bats" and .status == "detected"))' >/dev/null
}

@test "cog test-review-discover detects bats when no earlier runner matches" {
  local repo="${BATS_TEST_TMPDIR}/batsrepo"
  mkdir -p "$repo/tests"
  touch "$repo/tests/tool.bats"

  run cog test-review-discover --repo-root "$repo" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.runner.name == "bats" and .runner.command == ["bats","tests/"] and (.project.languages | index("bash"))' >/dev/null
}
