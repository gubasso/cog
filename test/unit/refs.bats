setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export LIB_DIR="${BATS_TEST_DIRNAME}/../../lib"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  mkdir -p "$HOME" "$XDG_STATE_HOME"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/helpers.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_refs.sh"
}

make_docs_tree() {
  local root="$1"
  mkdir -p \
    "$root/tech/programming/code-review" \
    "$root/tech/programming/cli-design" \
    "$root/tech/languages/bash/cli-spec" \
    "$root/tech/languages/bash"
  touch \
    "$root/tech/programming/code-review/AGENTS.md" \
    "$root/tech/programming/cli-design/AGENTS.md" \
    "$root/tech/languages/bash/code-review-guide.md" \
    "$root/tech/languages/bash/AGENTS.md" \
    "$root/tech/languages/bash/cli-spec/AGENTS.md"
}

@test "refs_resolve_docs_path prefers override" {
  local override="${BATS_TEST_TMPDIR}/override"
  local env_docs="${BATS_TEST_TMPDIR}/env"
  make_docs_tree "$override"
  make_docs_tree "$env_docs"
  # shellcheck disable=SC2030
  export DOCS_NOTES_REPO="$env_docs"

  run cog::fn::refs_resolve_docs_path "$override"

  assert_success
  assert_output "$override"
}

@test "refs_resolve_docs_path falls back to DOCS_NOTES_REPO" {
  local env_docs="${BATS_TEST_TMPDIR}/env"
  make_docs_tree "$env_docs"
  # shellcheck disable=SC2031
  export DOCS_NOTES_REPO="$env_docs"

  run cog::fn::refs_resolve_docs_path

  assert_success
  assert_output "$env_docs"
}

@test "refs_resolve_docs_path returns nonzero when no docs repo exists" {
  unset DOCS_NOTES_REPO

  run cog::fn::refs_resolve_docs_path "${BATS_TEST_TMPDIR}/missing"

  assert_failure
  assert_output ""
}

@test "refs_compute returns sorted unique refs and cli-specific paths" {
  local docs="${BATS_TEST_TMPDIR}/docs"
  make_docs_tree "$docs"

  run cog::fn::refs_compute "$docs" true bash bash missing

  assert_success
  assert_line "tech/languages/bash/AGENTS.md"
  assert_line "tech/languages/bash/cli-spec/AGENTS.md"
  assert_line "tech/languages/bash/code-review-guide.md"
  assert_line "tech/programming/cli-design/AGENTS.md"
  assert_line "tech/programming/code-review/AGENTS.md"
  [ "$(printf '%s\n' "$output" | sort | uniq | wc -l | tr -d ' ')" -eq "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" ]
}

@test "refs_compute omits cli refs when not cli" {
  local docs="${BATS_TEST_TMPDIR}/docs"
  make_docs_tree "$docs"

  run cog::fn::refs_compute "$docs" false bash

  assert_success
  [[ $output != *"cli-design"* ]]
  [[ $output != *"cli-spec"* ]]
}
