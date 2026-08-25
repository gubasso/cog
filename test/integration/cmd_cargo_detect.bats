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

@test "cog cargo-detect reports an unscaffolded project" {
  run cog cargo-detect --project-root "${BATS_TEST_TMPDIR}/repo" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .scaffolded == false and .kind == "none" and .edition == null' >/dev/null
}

@test "cog cargo-detect reports a scaffolded bin crate with edition" {
  printf '[package]\nname = "x"\nedition = "2021"\n\n[[bin]]\nname = "x"\n' >"${BATS_TEST_TMPDIR}/repo/Cargo.toml"

  run cog cargo-detect --project-root "${BATS_TEST_TMPDIR}/repo" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .scaffolded == true and .kind == "bin" and .edition == "2021"' >/dev/null
}

@test "cog cargo-detect classifies a lib crate" {
  printf '[package]\nname = "x"\nedition = "2021"\n' >"${BATS_TEST_TMPDIR}/repo/Cargo.toml"
  mkdir -p "${BATS_TEST_TMPDIR}/repo/src"
  touch "${BATS_TEST_TMPDIR}/repo/src/lib.rs"

  run cog cargo-detect --project-root "${BATS_TEST_TMPDIR}/repo" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.kind == "lib"' >/dev/null
}

@test "cog cargo-detect classifies a workspace" {
  printf '[workspace]\nmembers = ["a"]\n' >"${BATS_TEST_TMPDIR}/repo/Cargo.toml"

  run cog cargo-detect --project-root "${BATS_TEST_TMPDIR}/repo" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.kind == "workspace"' >/dev/null
}

@test "cog cargo-detect reports present optional configs" {
  printf '[package]\nname = "x"\n' >"${BATS_TEST_TMPDIR}/repo/Cargo.toml"
  touch "${BATS_TEST_TMPDIR}/repo/rustfmt.toml" "${BATS_TEST_TMPDIR}/repo/deny.toml"

  run cog cargo-detect --project-root "${BATS_TEST_TMPDIR}/repo" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.configs.rustfmt_toml == true and .configs.deny_toml == true and .configs.clippy_toml == false' >/dev/null
}

@test "cog cargo-detect --help dispatches" {
  run cog cargo-detect --help

  assert_success
  [[ $output == *"Detect Rust project scaffold state"* ]]
}
