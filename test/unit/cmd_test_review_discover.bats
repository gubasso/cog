setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export LIB_DIR="${BATS_TEST_DIRNAME}/../../lib"
  source "${LIB_DIR}/helpers.sh"
  source "${LIB_DIR}/functions/fn_ui_print.sh"
  source "${LIB_DIR}/functions/fn_log.sh"
  source "${LIB_DIR}/functions/fn_error_raise.sh"
  source "${LIB_DIR}/functions/fn_json_write.sh"
  source "${LIB_DIR}/commands/cmd_test_review_discover.sh"
}

@test "test-review-discover extracts tasks and file context" {
  local plan="${BATS_TEST_TMPDIR}/REFACTOR_PLAN.md"
  cat >"$plan" <<'EOF'
File: tests/test_app.py
- [ ] T-PY-001 pending task
- [x] T-PY-002 done task
## Next
- [ ] T-JS-003 file: tests/app.test.js, pending js
EOF

  run __cog_test_review_discover_extract_tasks_json "$plan"

  assert_success
  printf '%s\n' "$output" | jq -e '
    length == 3 and
    (.[0] == {id:"T-PY-001", done:false, file:"tests/test_app.py"}) and
    (.[1] == {id:"T-PY-002", done:true, file:"tests/test_app.py"}) and
    (.[2].id == "T-JS-003" and .[2].file == "tests/app.test.js")
  ' >/dev/null
}
