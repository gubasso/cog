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

@test "cog cargo-scaffold-apply is a no-op on an already-scaffolded project" {
  printf '[package]\nname = "x"\n' >"${BATS_TEST_TMPDIR}/repo/Cargo.toml"

  run cog cargo-scaffold-apply --project-root "${BATS_TEST_TMPDIR}/repo" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and (.ran | length) == 0 and (.skipped[] | select(.action == "cargo-init"))' >/dev/null
}

@test "cog cargo-scaffold-apply skips deny init when deny.toml exists" {
  printf '[package]\nname = "x"\n' >"${BATS_TEST_TMPDIR}/repo/Cargo.toml"
  touch "${BATS_TEST_TMPDIR}/repo/deny.toml"

  run cog cargo-scaffold-apply --project-root "${BATS_TEST_TMPDIR}/repo" --deny-init --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and (.skipped[] | select(.action == "cargo-deny-init"))' >/dev/null
}

@test "cog cargo-scaffold-apply rejects an invalid --kind" {
  run --separate-stderr cog cargo-scaffold-apply --project-root "${BATS_TEST_TMPDIR}/repo" --kind app --json

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and (.reason | test("kind"))' >/dev/null
}

@test "cog cargo-scaffold-apply fails legibly when cargo is unreachable" {
  if command -v cargo >/dev/null 2>&1; then
    skip "cargo is reachable in this environment"
  fi

  run --separate-stderr cog cargo-scaffold-apply --project-root "${BATS_TEST_TMPDIR}/repo" --json

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and .cargo_runner == "absent"' >/dev/null
}

@test "cog cargo-scaffold-apply --help dispatches" {
  run cog cargo-scaffold-apply --help

  assert_success
  [[ $output == *"Scaffold a Rust project with the cargo CLI"* ]]
}
