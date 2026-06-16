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
  source "${LIB_DIR}/functions/fn_refs.sh"
  source "${LIB_DIR}/commands/cmd_review_refs.sh"
}

@test "review-refs JSON array helper encodes refs" {
  run __cog_review_refs_json_array a b

  assert_success
  printf '%s\n' "$output" | jq -e '. == ["a","b"]' >/dev/null
}

@test "review-refs supports positional classification" {
  local docs="${BATS_TEST_TMPDIR}/docs"
  mkdir -p "${docs}/tech"
  printf '%s\n' '{"is_cli":false,"languages":[]}' >"${BATS_TEST_TMPDIR}/classification.json"

  run cog::cmd::review_refs "${BATS_TEST_TMPDIR}/classification.json" --docs-notes-repo "$docs" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.docs_notes_repo.available == true and .docs_notes_repo.path == "'"$docs"'"' >/dev/null
}

@test "review-refs rejects extra arguments" {
  run --separate-stderr cog::cmd::review_refs a b c

  assert_failure 64
  [[ $stderr == *"err.kind: TooManyArguments"* ]]
}
