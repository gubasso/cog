setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export LIB_DIR="${BATS_TEST_DIRNAME}/../../lib"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/helpers.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_ui_print.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_log.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_error_raise.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_scope_declaration.sh"
}

# Validate a literal declaration through the shared filter.
accepts() {
  jq -e "$(cog::fn::scope_declaration_filter)" <<<"$1" >/dev/null 2>&1
}

@test "scope declaration accepts every field and any subset" {
  accepts '{}'
  accepts '{"worktree": true}'
  accepts '{"shas": ["abc"]}'
  accepts '{"worktree": false, "ranges": ["a..b"]}'
  accepts '{"worktree": false, "files": ["lib/a.sh"]}'
  accepts '{"worktree": true, "ranges": [], "shas": [], "files": []}'
}

@test "scope declaration rejects an unknown key" {
  run accepts '{"nope": true}'
  assert_failure
}

@test "scope declaration rejects a non-object" {
  run accepts '"abc"'
  assert_failure
  run accepts '[]'
  assert_failure
}

@test "scope declaration rejects an empty or non-string selector" {
  run accepts '{"shas": [""]}'
  assert_failure
  run accepts '{"shas": [1]}'
  assert_failure
  run accepts '{"ranges": "a..b"}'
  assert_failure
}

@test "scope declaration rejects an explicit null in place of a default" {
  # An explicit null must not read as absent: falling back to the default here
  # turns a malformed declaration into a silent working-tree scope.
  run accepts '{"worktree": null}'
  assert_failure
  run accepts '{"shas": null}'
  assert_failure
}

@test "scope declaration rejects a files entry outside the repo" {
  run accepts '{"files": ["/etc/passwd"]}'
  assert_failure
  run accepts '{"files": ["../outside.txt"]}'
  assert_failure
  run accepts '{"files": ["lib/../../outside.txt"]}'
  assert_failure
}

@test "scope declaration rejects a declaration naming no source" {
  # worktree off and nothing else named resolves to nothing, and an empty scope
  # reads as a clean review everywhere downstream.
  run accepts '{"worktree": false}'
  assert_failure
  run accepts '{"worktree": false, "ranges": [], "shas": [], "files": []}'
  assert_failure
}

@test "scope declaration normalizes every optional field" {
  local decl="${BATS_TEST_TMPDIR}/decl.json"
  printf '%s' '{"shas": ["abc"]}' >"$decl"

  run cog::fn::scope_declaration_read "$decl"

  assert_success
  printf '%s\n' "$output" | jq -e '. == {worktree: true, ranges: [], shas: ["abc"], files: []}' >/dev/null
}

@test "scope declaration preserves an explicit worktree false" {
  # jq's `//` yields its right side for false as well as null, so a normalize
  # written with `.worktree // true` silently re-enables the tree.
  local decl="${BATS_TEST_TMPDIR}/decl.json"
  printf '%s' '{"worktree": false, "shas": ["abc"]}' >"$decl"

  run cog::fn::scope_declaration_read "$decl"

  assert_success
  printf '%s\n' "$output" | jq -e '.worktree == false' >/dev/null
}

@test "scope declaration read fails closed on a missing or malformed file" {
  run --separate-stderr cog::fn::scope_declaration_read "${BATS_TEST_TMPDIR}/absent.json"
  assert_failure
  [[ $stderr == *"err.kind: InputNotFound"* ]]

  local decl="${BATS_TEST_TMPDIR}/bad.json"
  printf '%s' 'not json' >"$decl"
  run --separate-stderr cog::fn::scope_declaration_read "$decl"
  assert_failure
  [[ $stderr == *"not valid JSON"* ]]
}

@test "scope declaration default is the working tree alone" {
  run cog::fn::scope_declaration_default

  assert_success
  printf '%s\n' "$output" | jq -e '. == {worktree: true, ranges: [], shas: [], files: []}' >/dev/null
}
