setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_DATA_HOME="${BATS_TEST_TMPDIR}/data"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  unset RUN_DIR DOCS_NOTES_REPO REFACTOR_GUIDELINE RIPTASK_REPO
  mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "${BATS_TEST_TMPDIR}/repo/src/bin"
}

@test "cog classify-project detects rust cli shape" {
  cat >"${BATS_TEST_TMPDIR}/repo/Cargo.toml" <<'EOF'
[package]
name = "demo"

[[bin]]
name = "demo"

[dependencies]
clap = "4"
EOF

  run bash -c 'cd "$1" && cog classify-project --json' _ "${BATS_TEST_TMPDIR}/repo"

  assert_success
  printf '%s\n' "$output" | jq -e '.is_cli == true and (.languages[] | select(.lang == "rust")) and (.frameworks[] | select(.name == "clap"))' >/dev/null
}

@test "cog classify-project writes a fragment" {
  touch "${BATS_TEST_TMPDIR}/repo/package.json"
  local out="${BATS_TEST_TMPDIR}/classification.json"

  run bash -c 'cd "$1" && cog classify-project "$2"' _ "${BATS_TEST_TMPDIR}/repo" "$out"

  assert_success
  assert_output "RESOLVED $out"
  jq -e '.git_root and (.languages[] | select(.lang == "javascript"))' "$out" >/dev/null
}

@test "cog classify-project --help dispatches" {
  run cog classify-project --help

  assert_success
  [[ $output == *"Classify repository shape"* ]]
}
