setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  REPO="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "$REPO"
  git -C "$REPO" init -q
  git -C "$REPO" config user.email t@t
  git -C "$REPO" config user.name t
  printf 'a\nb\nc\n' >"$REPO/f1.txt"
  printf 'x\ny\n' >"$REPO/f2.txt"
  git -C "$REPO" add -A
}

@test "review-scope check passes within declared limits" {
  cd "$REPO"
  run cog review-scope check --max-files 5 --max-lines 100 --json
  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .exceeded == false and (.breaches == [])' >/dev/null
}

@test "review-scope check fails and names the files breach" {
  cd "$REPO"
  run cog review-scope check --max-files 1 --json
  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and .exceeded == true and (.breaches | index("files"))' >/dev/null
}

@test "review-scope check fails and names the lines breach" {
  cd "$REPO"
  run cog review-scope check --max-lines 2 --json
  assert_failure
  printf '%s\n' "$output" | jq -e '(.breaches | index("lines"))' >/dev/null
}

@test "review-scope check at the exact limit passes" {
  cd "$REPO"
  run cog review-scope check --max-files 2 --json
  assert_success
  printf '%s\n' "$output" | jq -e '.exceeded == false' >/dev/null
}

@test "review-scope check requires at least one limit" {
  cd "$REPO"
  run --separate-stderr cog review-scope check --json
  assert_failure
  [[ $stderr == *"missing scope limit"* ]]
}

@test "bare review-scope still emits its full report" {
  cd "$REPO"
  run cog review-scope --json
  assert_success
  printf '%s\n' "$output" | jq -e '(.changed_files | type == "array") and (.diff_stats | type == "object")' >/dev/null
}
