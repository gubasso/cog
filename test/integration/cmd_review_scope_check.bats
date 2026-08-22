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

# A second fixture with real history. The setup repo above is deliberately
# commit-less, which is what proves no code path here reaches for HEAD.
committed_repo() {
  local repo="${BATS_TEST_TMPDIR}/committed"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email t@t
  git -C "$repo" config user.name t
  printf 'a\nb\nc\nd\n' >"$repo/committed.txt"
  git -C "$repo" add -A
  git -C "$repo" commit -qm "seed"
  printf '%s\n' "$repo"
}

@test "review-scope check counts a commit selector against the file limit" {
  local repo
  repo="$(committed_repo)"
  cd "$repo"
  # Outside the repo on purpose: a declaration written inside the fixture is
  # itself an untracked path and lands in the scope it declares.
  printf '%s' '{"shas":["HEAD"]}' >"${BATS_TEST_TMPDIR}/declaration.json"
  run cog review-scope check --max-files 0 --declaration "${BATS_TEST_TMPDIR}/declaration.json" --json
  assert_failure
  printf '%s\n' "$output" | jq -e '.actual.files == 1 and (.breaches | index("files"))' >/dev/null
}

@test "review-scope check counts only the commit lines when the tree is excluded" {
  local repo
  repo="$(committed_repo)"
  cd "$repo"
  printf 'x\n' >>"$repo/committed.txt"
  printf '%s' '{"worktree":false,"shas":["HEAD"]}' >"${BATS_TEST_TMPDIR}/declaration.json"
  run cog review-scope check --declaration "${BATS_TEST_TMPDIR}/declaration.json" --max-lines 100 --json
  assert_success
  printf '%s\n' "$output" | jq -e '.actual.lines == 4' >/dev/null
}
