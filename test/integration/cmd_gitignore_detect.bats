setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_DATA_HOME="${BATS_TEST_TMPDIR}/data"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  unset RUN_DIR REFACTOR_GUIDELINE
  mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "${BATS_TEST_TMPDIR}/repo"
}

@test "cog gitignore-detect uses bundled default template root" {
  touch "${BATS_TEST_TMPDIR}/repo/Cargo.toml"

  run cog gitignore-detect --project-root "${BATS_TEST_TMPDIR}/repo" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .detected_type == "rust" and (.template_root | endswith("/templates/gitignore"))' >/dev/null
}

@test "cog gitignore-detect falls back to generic for an unrecognized project" {
  touch "${BATS_TEST_TMPDIR}/repo/random.xyz"

  run cog gitignore-detect --project-root "${BATS_TEST_TMPDIR}/repo" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .detected_type == "generic" and .confidence == "fallback"' >/dev/null
}

@test "cog gitignore-detect falls back to generic on ambiguous signals" {
  touch "${BATS_TEST_TMPDIR}/repo/Cargo.toml" "${BATS_TEST_TMPDIR}/repo/package.json"

  run cog gitignore-detect --project-root "${BATS_TEST_TMPDIR}/repo" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .detected_type == "generic" and (.conflicts | index("rust")) and (.conflicts | index("node"))' >/dev/null
}

@test "cog gitignore-detect fails an explicit unknown --type instead of masking as generic" {
  touch "${BATS_TEST_TMPDIR}/repo/random.xyz"

  run --separate-stderr cog gitignore-detect --project-root "${BATS_TEST_TMPDIR}/repo" --type bogus --json

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and .requested_type == "bogus" and .detected_type != "generic" and .reason == "template config not found"' >/dev/null
}

@test "cog gitignore-detect preserves a bad project root error" {
  run --separate-stderr cog gitignore-detect --project-root "${BATS_TEST_TMPDIR}/missing" --json

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and .reason == "project root is not a directory"' >/dev/null
}

@test "cog gitignore-detect --help dispatches" {
  run cog gitignore-detect --help

  assert_success
  [[ $output == *"Detect gitignore template type"* ]]
}
