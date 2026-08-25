setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_DATA_HOME="${BATS_TEST_TMPDIR}/data"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  unset RUN_DIR
  mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "${BATS_TEST_TMPDIR}/repo"
}

@test "cog nix-devshell-detect maps a rust project to the rust template" {
  touch "${BATS_TEST_TMPDIR}/repo/Cargo.toml"

  run cog nix-devshell-detect --project-root "${BATS_TEST_TMPDIR}/repo" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .detected_type == "rust" and .confidence == "high" and (.template_root | endswith("/templates/nix"))' >/dev/null
}

@test "cog nix-devshell-detect maps a node project to the node template" {
  printf '{}' >"${BATS_TEST_TMPDIR}/repo/package.json"

  run cog nix-devshell-detect --project-root "${BATS_TEST_TMPDIR}/repo" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .detected_type == "node"' >/dev/null
}

@test "cog nix-devshell-detect falls back to generic for an unrecognized project" {
  run cog nix-devshell-detect --project-root "${BATS_TEST_TMPDIR}/repo" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .detected_type == "generic" and .confidence == "fallback"' >/dev/null
}

@test "cog nix-devshell-detect falls back to generic on ambiguous signals" {
  touch "${BATS_TEST_TMPDIR}/repo/Cargo.toml"
  printf '[tool.poetry]\n' >"${BATS_TEST_TMPDIR}/repo/pyproject.toml"

  run cog nix-devshell-detect --project-root "${BATS_TEST_TMPDIR}/repo" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .detected_type == "generic" and .confidence == "fallback"' >/dev/null
}

@test "cog nix-devshell-detect honors an explicit --type" {
  run cog nix-devshell-detect --project-root "${BATS_TEST_TMPDIR}/repo" --type zig --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .detected_type == "zig" and .confidence == "requested"' >/dev/null
}

@test "cog nix-devshell-detect rejects an invalid --type" {
  run --separate-stderr cog nix-devshell-detect --project-root "${BATS_TEST_TMPDIR}/repo" --type 'BAD!' --json

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false' >/dev/null
}

@test "cog nix-devshell-detect --help dispatches" {
  run cog nix-devshell-detect --help

  assert_success
  [[ $output == *"Detect nix devshell template type"* ]]
}
