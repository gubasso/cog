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

@test "cog cargo-publish-apply copies scripts and PUBLISHING.md" {
  run cog cargo-publish-apply --project-root "${BATS_TEST_TMPDIR}/repo" --doc-dir . --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and (.copied|length) >= 4' >/dev/null
  test -x "${BATS_TEST_TMPDIR}/repo/scripts/publish"
  test -x "${BATS_TEST_TMPDIR}/repo/scripts/publish-dry"
  test -f "${BATS_TEST_TMPDIR}/repo/PUBLISHING.md"
}

@test "cog cargo-publish-apply lands PUBLISHING.md under docs/ when requested" {
  mkdir -p "${BATS_TEST_TMPDIR}/repo/docs"
  run cog cargo-publish-apply --project-root "${BATS_TEST_TMPDIR}/repo" --doc-dir docs --json

  assert_success
  test -f "${BATS_TEST_TMPDIR}/repo/docs/PUBLISHING.md"
}

@test "cog cargo-publish-apply includes release-plz.toml with --with-release-plz" {
  run cog cargo-publish-apply --project-root "${BATS_TEST_TMPDIR}/repo" --doc-dir . --with-release-plz --json

  assert_success
  test -f "${BATS_TEST_TMPDIR}/repo/release-plz.toml"
}

@test "cog cargo-publish-apply includes dist-workspace.toml with --with-dist" {
  run cog cargo-publish-apply --project-root "${BATS_TEST_TMPDIR}/repo" --doc-dir . --with-dist --json

  assert_success
  test -f "${BATS_TEST_TMPDIR}/repo/dist-workspace.toml"
}

@test "cog cargo-publish-apply aborts on a pre-existing destination" {
  mkdir -p "${BATS_TEST_TMPDIR}/repo/scripts"
  printf 'old\n' >"${BATS_TEST_TMPDIR}/repo/scripts/publish"
  run cog cargo-publish-apply --project-root "${BATS_TEST_TMPDIR}/repo" --doc-dir . --conflict abort --json

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and (.conflicts|length) >= 1' >/dev/null
}

@test "cog cargo-publish-apply skips existing destinations under --conflict skip" {
  mkdir -p "${BATS_TEST_TMPDIR}/repo/scripts"
  printf 'old\n' >"${BATS_TEST_TMPDIR}/repo/scripts/publish"
  run cog cargo-publish-apply --project-root "${BATS_TEST_TMPDIR}/repo" --doc-dir . --conflict skip --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and (.skipped|length) >= 1' >/dev/null
  [[ "$(cat "${BATS_TEST_TMPDIR}/repo/scripts/publish")" == "old" ]]
}

@test "cog cargo-publish-apply overwrites existing destinations under --conflict overwrite" {
  mkdir -p "${BATS_TEST_TMPDIR}/repo/scripts"
  printf 'old\n' >"${BATS_TEST_TMPDIR}/repo/scripts/publish"
  run cog cargo-publish-apply --project-root "${BATS_TEST_TMPDIR}/repo" --doc-dir . --conflict overwrite --json

  assert_success
  [[ "$(cat "${BATS_TEST_TMPDIR}/repo/scripts/publish")" != "old" ]]
}

@test "cog cargo-publish-apply --help dispatches" {
  run cog cargo-publish-apply --help

  assert_success
  [[ $output == *"Apply Rust cargo publishing helper templates"* ]]
}
