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

@test "cog installer-detect resolves rust from Cargo.toml" {
  printf '[package]\nname = "x"\n' >"${BATS_TEST_TMPDIR}/repo/Cargo.toml"

  run cog installer-detect --project-root "${BATS_TEST_TMPDIR}/repo" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .detected_type == "rust" and .template_exists == true' >/dev/null
}

@test "cog installer-detect honors an explicit --type generic" {
  run cog installer-detect --project-root "${BATS_TEST_TMPDIR}/repo" --type generic --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .detected_type == "generic" and .confidence == "requested"' >/dev/null
}

@test "cog installer-detect fails to classify an empty project" {
  run --separate-stderr cog installer-detect --project-root "${BATS_TEST_TMPDIR}/repo" --json

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and .reason == "could not detect template type"' >/dev/null
}

@test "cog installer-detect writes a JSON fragment to a file" {
  run cog installer-detect --project-root "${BATS_TEST_TMPDIR}/repo" --type bash "${BATS_TEST_TMPDIR}/out.json"

  assert_success
  [ -f "${BATS_TEST_TMPDIR}/out.json" ]
  jq -e '.ok == true and .detected_type == "bash"' "${BATS_TEST_TMPDIR}/out.json" >/dev/null
}
