setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_DATA_HOME="${BATS_TEST_TMPDIR}/data"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  unset RUN_DIR DOCS_NOTES_REPO REFACTOR_GUIDELINE RIPTASK_REPO
  mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "${BATS_TEST_TMPDIR}/repo"
}

@test "cog cargo-publish-detect reports an empty non-Rust dir" {
  run cog cargo-publish-detect --project-root "${BATS_TEST_TMPDIR}/repo" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .crate_kind == "none" and .is_publishable == false and .ci_provider == "none"' >/dev/null
}

@test "cog cargo-publish-detect classifies a lib crate as not shipping binaries" {
  printf '[package]\nname = "x"\n' >"${BATS_TEST_TMPDIR}/repo/Cargo.toml"
  mkdir -p "${BATS_TEST_TMPDIR}/repo/src"
  touch "${BATS_TEST_TMPDIR}/repo/src/lib.rs"

  run cog cargo-publish-detect --project-root "${BATS_TEST_TMPDIR}/repo" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.crate_kind == "lib" and .is_publishable == true and .ships_binaries.hint == false' >/dev/null
}

@test "cog cargo-publish-detect hints binaries for a bin crate" {
  printf '[package]\nname = "x"\n' >"${BATS_TEST_TMPDIR}/repo/Cargo.toml"
  mkdir -p "${BATS_TEST_TMPDIR}/repo/src"
  touch "${BATS_TEST_TMPDIR}/repo/src/main.rs"

  run cog cargo-publish-detect --project-root "${BATS_TEST_TMPDIR}/repo" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.crate_kind == "bin" and .ships_binaries.hint == true' >/dev/null
}

@test "cog cargo-publish-detect honors publish = false" {
  printf '[package]\nname = "x"\npublish = false\n' >"${BATS_TEST_TMPDIR}/repo/Cargo.toml"

  run cog cargo-publish-detect --project-root "${BATS_TEST_TMPDIR}/repo" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.is_publishable == false' >/dev/null
}

@test "cog cargo-publish-detect detects a github ci provider" {
  printf '[package]\nname = "x"\n' >"${BATS_TEST_TMPDIR}/repo/Cargo.toml"
  mkdir -p "${BATS_TEST_TMPDIR}/repo/.github/workflows"
  printf 'on: push\n' >"${BATS_TEST_TMPDIR}/repo/.github/workflows/ci.yml"

  run cog cargo-publish-detect --project-root "${BATS_TEST_TMPDIR}/repo" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ci_provider == "github"' >/dev/null
}

@test "cog cargo-publish-detect detects a gitlab ci provider" {
  printf '[package]\nname = "x"\n' >"${BATS_TEST_TMPDIR}/repo/Cargo.toml"
  printf 'stages:\n' >"${BATS_TEST_TMPDIR}/repo/.gitlab-ci.yml"

  run cog cargo-publish-detect --project-root "${BATS_TEST_TMPDIR}/repo" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ci_provider == "gitlab"' >/dev/null
}

@test "cog cargo-publish-detect detects release-plz and its native semver check" {
  printf '[package]\nname = "x"\n' >"${BATS_TEST_TMPDIR}/repo/Cargo.toml"
  printf '[workspace]\n' >"${BATS_TEST_TMPDIR}/repo/release-plz.toml"

  run cog cargo-publish-detect --project-root "${BATS_TEST_TMPDIR}/repo" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.release_tool.name == "release-plz" and .semver_tool.present == true' >/dev/null
}

@test "cog cargo-publish-detect detects a standalone semver-checks reference" {
  printf '[package]\nname = "x"\n' >"${BATS_TEST_TMPDIR}/repo/Cargo.toml"
  mkdir -p "${BATS_TEST_TMPDIR}/repo/.github/workflows"
  printf 'run: cargo semver-checks check-release\n' >"${BATS_TEST_TMPDIR}/repo/.github/workflows/semver.yml"

  run cog cargo-publish-detect --project-root "${BATS_TEST_TMPDIR}/repo" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.semver_tool.present == true' >/dev/null
}

@test "cog cargo-publish-detect --help dispatches" {
  run cog cargo-publish-detect --help

  assert_success
  [[ $output == *"Detect Rust crate publishing readiness"* ]]
}
