setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
}

make_docs_tree() {
  local root="$1"
  mkdir -p "$root/tech/programming/code-review" "$root/tech/programming/cli-design" "$root/tech/languages/bash/cli-spec" "$root/tech/languages/bash"
  touch "$root/tech/programming/code-review/AGENTS.md" "$root/tech/programming/cli-design/AGENTS.md" "$root/tech/languages/bash/code-review-guide.md" "$root/tech/languages/bash/AGENTS.md" "$root/tech/languages/bash/cli-spec/AGENTS.md"
}

write_classification() {
  cat >"${BATS_TEST_TMPDIR}/classification.json" <<'JSON'
{"is_cli":true,"languages":[{"lang":"bash"}]}
JSON
}

@test "cog review-refs resolves docs references" {
  local docs="${BATS_TEST_TMPDIR}/docs"
  make_docs_tree "$docs"
  write_classification

  run cog review-refs --classification "${BATS_TEST_TMPDIR}/classification.json" --docs-notes-repo "$docs" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.docs_notes_repo.available == true and (.docs_notes_repo.relevant_agents_md | index("tech/languages/bash/cli-spec/AGENTS.md"))' >/dev/null
}

@test "cog review-refs handles missing docs repo" {
  write_classification

  run cog review-refs --classification "${BATS_TEST_TMPDIR}/classification.json" --docs-notes-repo "${BATS_TEST_TMPDIR}/missing" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.docs_notes_repo.available == false and .docs_notes_repo.relevant_agents_md == []' >/dev/null
}

@test "cog review-refs rejects invalid classification" {
  printf '%s\n' "{" >"${BATS_TEST_TMPDIR}/bad.json"

  run --separate-stderr cog review-refs --classification "${BATS_TEST_TMPDIR}/bad.json" --json

  assert_failure
  [[ $stderr == *"err.kind: InvalidJsonInput"* ]]
}

@test "cog review-refs --help dispatches" {
  run cog review-refs --help

  assert_success
  [[ $output == *"Resolve docs-n-notes"* ]]
}
