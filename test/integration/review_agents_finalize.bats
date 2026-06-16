setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
}

make_docs_tree() {
  local root="$1"
  mkdir -p "$root/tech/programming/code-review"
  touch "$root/tech/programming/code-review/AGENTS.md"
}

@test "cog review-agents-finalize delegates to review-refs" {
  local docs="${BATS_TEST_TMPDIR}/docs"
  make_docs_tree "$docs"
  printf '%s\n' '{"is_cli":false,"languages":[]}' >"${BATS_TEST_TMPDIR}/classification.json"

  run cog review-agents-finalize --classification "${BATS_TEST_TMPDIR}/classification.json" --docs-notes-repo "$docs" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.docs_notes_repo.available == true and .docs_notes_repo.relevant_agents_md == ["tech/programming/code-review/AGENTS.md"]' >/dev/null
}

@test "cog review-agents-finalize rejects invalid classification" {
  printf '%s\n' "{" >"${BATS_TEST_TMPDIR}/bad.json"

  run --separate-stderr cog review-agents-finalize --classification "${BATS_TEST_TMPDIR}/bad.json" --json

  assert_failure
  [[ $stderr == *"err.kind: InvalidJsonInput"* ]]
}

@test "cog review-agents-finalize --help dispatches" {
  run cog review-agents-finalize --help

  assert_success
  [[ $output == *"Finalize review reference"* ]]
}
