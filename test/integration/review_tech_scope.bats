setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_DATA_HOME="${BATS_TEST_TMPDIR}/data"
  mkdir -p "$HOME" "${XDG_DATA_HOME}/cog/skill-refs/code-review/languages/python" "${XDG_DATA_HOME}/cog/skill-refs/code-review/languages/javascript"
  printf '%s\n' "core" >"${XDG_DATA_HOME}/cog/skill-refs/code-review/AGENTS.md"
  printf '%s\n' "python" >"${XDG_DATA_HOME}/cog/skill-refs/code-review/languages/python/code-review-guide.md"
  printf '%s\n' "javascript" >"${XDG_DATA_HOME}/cog/skill-refs/code-review/languages/javascript/code-review-guide.md"
}

@test "cog review-tech-scope detects mixed changed files" {
  local repo="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "$repo"
  printf '%s\n' 'import click' >"$repo/app.py"
  printf '%s\n' 'console.log("x")' >"$repo/app.js"
  jq -n --arg repo "$repo" '{repo_root: $repo, changed_files: ["app.py","app.js"], status_files: []}' >"${BATS_TEST_TMPDIR}/scope.json"

  run cog review-tech-scope --scope "${BATS_TEST_TMPDIR}/scope.json" --json

  assert_success
  printf '%s\n' "$output" | jq -e '
    (.detected_technologies[] | select(.kind == "language" and .name == "python"))
    and (.detected_technologies[] | select(.kind == "framework" and .name == "click"))
    and (.research_targets[] | select(.name == "click"))
  ' >/dev/null
}

@test "cog review-tech-scope writes fragments" {
  local repo="${BATS_TEST_TMPDIR}/repo"
  local out="${BATS_TEST_TMPDIR}/tech.json"
  mkdir -p "$repo"
  printf '%s\n' 'print("x")' >"$repo/app.py"
  jq -n --arg repo "$repo" '{repo_root: $repo, changed_files: ["app.py"], status_files: []}' >"${BATS_TEST_TMPDIR}/scope.json"

  run cog review-tech-scope --scope "${BATS_TEST_TMPDIR}/scope.json" "$out"

  assert_success
  assert_output "RESOLVED $out"
  jq -e '.available_refs | index("code-review/languages/python/code-review-guide.md")' "$out" >/dev/null
}
