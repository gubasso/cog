# shellcheck shell=bash

setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export LIB_DIR="${BATS_TEST_DIRNAME}/../../lib"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  mkdir -p "$HOME" "$XDG_STATE_HOME"
  source "${LIB_DIR}/helpers.sh"
  source "${LIB_DIR}/functions/fn_ui_print.sh"
  source "${LIB_DIR}/functions/fn_log.sh"
  source "${LIB_DIR}/functions/fn_error_raise.sh"
  source "${LIB_DIR}/functions/fn_git.sh"

  REPO="${BATS_TEST_TMPDIR}/repo"
  git init -q "$REPO"
  git -C "$REPO" config user.email a@b.c
  git -C "$REPO" config user.name t
}

commit() {
  local subject="$1"
  shift
  printf '%s\n' "$subject" >"$REPO/${RANDOM}-${RANDOM}.txt"
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m "$subject" "$@"
}

@test "parses a scoped conventional subject" {
  run cog::fn::git_parse_conventional_subject "feat(api): add token refresh"
  assert_success
  jq -e '.sep_present == true and .type == "feat" and .scope == "api" and .description == "add token refresh" and .breaking == false' <<<"$output" >/dev/null
}

@test "parses a breaking-change marker" {
  run cog::fn::git_parse_conventional_subject "feat(api)!: drop v1"
  assert_success
  jq -e '.breaking == true and .type == "feat" and .scope == "api"' <<<"$output" >/dev/null
}

@test "parses a hierarchical scope" {
  run cog::fn::git_parse_conventional_subject "fix(core/db): handle null rows"
  assert_success
  jq -e '.type == "fix" and .scope == "core/db"' <<<"$output" >/dev/null
}

@test "flags a subject with no separator" {
  run cog::fn::git_parse_conventional_subject "add a thing without a type"
  assert_success
  jq -e '.sep_present == false and .type == "" and .scope == ""' <<<"$output" >/dev/null
}

@test "flags a missing space after the colon" {
  run cog::fn::git_parse_conventional_subject "refactor:no space"
  assert_success
  jq -e '.space_after_colon == false and .type == "refactor" and .description == "no space"' <<<"$output" >/dev/null
}

@test "flags an unbalanced-paren scope as malformed" {
  run cog::fn::git_parse_conventional_subject "feat(api: broken parens"
  assert_success
  jq -e '.scope_malformed == true and .type == "feat"' <<<"$output" >/dev/null
}

@test "matched parens with a spaced scope are not malformed" {
  run cog::fn::git_parse_conventional_subject "feat(a b): do the thing"
  assert_success
  jq -e '.scope_malformed == false and .scope == "a b"' <<<"$output" >/dev/null
}

@test "git_log_range_json returns parsed commits for a range" {
  commit "feat(api): one"
  commit "refactor(api): two"
  commit "fix(db): three"
  run cog::fn::git_log_range_json --repo "$REPO" --range HEAD~2..HEAD
  assert_success
  jq -e 'length == 2 and (.[0] | has("sha") and has("short") and has("type") and has("scope") and has("description") and has("breaking"))' <<<"$output" >/dev/null
}

@test "git_log_range_json resolves explicit non-contiguous shas" {
  commit "feat(api): one"
  local first
  first="$(git -C "$REPO" rev-parse HEAD)"
  commit "fix(db): two"
  run cog::fn::git_log_range_json --repo "$REPO" --sha "$first"
  assert_success
  jq -e 'length == 1 and .[0].type == "feat"' <<<"$output" >/dev/null
}

@test "git_log_range_json de-duplicates overlapping selectors" {
  commit "feat(api): one"
  commit "refactor(api): two"
  run cog::fn::git_log_range_json --repo "$REPO" --range HEAD~1..HEAD --sha "$(git -C "$REPO" rev-parse HEAD)"
  assert_success
  jq -e 'length == 1' <<<"$output" >/dev/null
}

@test "git_log_range_json preserves a multi-paragraph body" {
  commit "chore: base"
  commit "feat(api): one" -m "first body paragraph" -m "second body paragraph"
  run cog::fn::git_log_range_json --repo "$REPO" --range HEAD~1..HEAD
  assert_success
  jq -e '.[0].body | contains("first body paragraph") and contains("second body paragraph")' <<<"$output" >/dev/null
}

@test "git_log_range_json returns an empty array with no selectors" {
  run cog::fn::git_log_range_json --repo "$REPO"
  assert_success
  jq -e 'length == 0' <<<"$output" >/dev/null
}
