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

@test "cog ci-apply writes the github workflow under .github/workflows" {
  run cog ci-apply --project-root "${BATS_TEST_TMPDIR}/repo" --target github --json

  assert_success
  [ -f "${BATS_TEST_TMPDIR}/repo/.github/workflows/ci.yml" ]
  printf '%s\n' "$output" | jq -e '.ok == true and ([.copied[].dst] | any(endswith("/.github/workflows/ci.yml")))' >/dev/null
}

@test "cog ci-apply writes the gitlab pipeline at the project root" {
  run cog ci-apply --project-root "${BATS_TEST_TMPDIR}/repo" --target gitlab --json

  assert_success
  [ -f "${BATS_TEST_TMPDIR}/repo/.gitlab-ci.yml" ]
  printf '%s\n' "$output" | jq -e '[.copied[].dst] | any(endswith("/.gitlab-ci.yml"))' >/dev/null
}

@test "cog ci-apply --with-release also lands the release workflow, cliff.toml, and VERSION" {
  run cog ci-apply --project-root "${BATS_TEST_TMPDIR}/repo" --target github --with-release --json

  assert_success
  [ -f "${BATS_TEST_TMPDIR}/repo/.github/workflows/ci.yml" ]
  [ -f "${BATS_TEST_TMPDIR}/repo/.github/workflows/release.yml" ]
  [ -f "${BATS_TEST_TMPDIR}/repo/cliff.toml" ]
  [ -f "${BATS_TEST_TMPDIR}/repo/VERSION" ]
  printf '%s\n' "$output" | jq -e '.ok == true and ([.copied[].dst] | any(endswith("/.github/workflows/release.yml")) and any(endswith("/VERSION")) and any(endswith("/cliff.toml")))' >/dev/null
}

@test "cog ci-apply without --with-release leaves release files out" {
  run cog ci-apply --project-root "${BATS_TEST_TMPDIR}/repo" --target github --json

  assert_success
  [ ! -f "${BATS_TEST_TMPDIR}/repo/.github/workflows/release.yml" ]
  [ ! -f "${BATS_TEST_TMPDIR}/repo/VERSION" ]
}

@test "cog ci-apply rejects an unknown target" {
  run --separate-stderr cog ci-apply --project-root "${BATS_TEST_TMPDIR}/repo" --target bitbucket --json

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and .reason == "target must be github or gitlab"' >/dev/null
}

@test "cog ci-apply aborts on conflict" {
  mkdir -p "${BATS_TEST_TMPDIR}/repo/.github/workflows"
  touch "${BATS_TEST_TMPDIR}/repo/.github/workflows/ci.yml"

  run --separate-stderr cog ci-apply --project-root "${BATS_TEST_TMPDIR}/repo" --target github --json

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and .reason == "destination conflict"' >/dev/null
}

@test "cog ci-apply skips an existing file under skip policy" {
  mkdir -p "${BATS_TEST_TMPDIR}/repo/.github/workflows"
  printf 'name: keep\n' >"${BATS_TEST_TMPDIR}/repo/.github/workflows/ci.yml"

  run cog ci-apply --project-root "${BATS_TEST_TMPDIR}/repo" --target github --conflict skip --json

  assert_success
  printf '%s\n' "$output" | jq -e '[.skipped[].dst] | any(endswith("/.github/workflows/ci.yml"))' >/dev/null
  [ "$(cat "${BATS_TEST_TMPDIR}/repo/.github/workflows/ci.yml")" = "name: keep" ]
}

@test "cog ci-apply --help dispatches" {
  run cog ci-apply --help

  assert_success
  [[ $output == *"Apply a CI workflow template"* ]]
}
