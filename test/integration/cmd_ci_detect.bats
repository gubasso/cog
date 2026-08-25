setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_DATA_HOME="${BATS_TEST_TMPDIR}/data"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  unset RUN_DIR
  mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "${BATS_TEST_TMPDIR}/repo/.git"
}

_write_config() {
  printf '%s\n' "$1" >"${BATS_TEST_TMPDIR}/repo/.git/config"
}

@test "cog ci-detect classifies a github https remote" {
  _write_config '[remote "origin"]
  url = https://github.com/owner/repo.git'

  run cog ci-detect --project-root "${BATS_TEST_TMPDIR}/repo" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .host == "github" and .target == "github" and .requires_question == false' >/dev/null
}

@test "cog ci-detect classifies a github scp-style remote" {
  _write_config '[remote "origin"]
  url = git@github.com:owner/repo.git'

  run cog ci-detect --project-root "${BATS_TEST_TMPDIR}/repo" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.host == "github" and .target == "github"' >/dev/null
}

@test "cog ci-detect classifies a gitlab remote" {
  _write_config '[remote "origin"]
  url = git@gitlab.com:owner/repo.git'

  run cog ci-detect --project-root "${BATS_TEST_TMPDIR}/repo" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.host == "gitlab" and .target == "gitlab" and .requires_question == false' >/dev/null
}

@test "cog ci-detect reports none with no remote" {
  _write_config '[core]
  bare = false'

  run cog ci-detect --project-root "${BATS_TEST_TMPDIR}/repo" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .host == "none" and .target == "none" and .requires_question == true and .remote_url == null' >/dev/null
}

@test "cog ci-detect reports other for an unsupported host" {
  _write_config '[remote "origin"]
  url = git@bitbucket.org:owner/repo.git'

  run cog ci-detect --project-root "${BATS_TEST_TMPDIR}/repo" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.host == "other" and .target == "none" and .requires_question == true' >/dev/null
}

@test "cog ci-detect surfaces existing CI files" {
  _write_config '[remote "origin"]
  url = https://github.com/owner/repo.git'
  mkdir -p "${BATS_TEST_TMPDIR}/repo/.github/workflows"
  touch "${BATS_TEST_TMPDIR}/repo/.github/workflows/ci.yml"

  run cog ci-detect --project-root "${BATS_TEST_TMPDIR}/repo" --json

  assert_success
  printf '%s\n' "$output" | jq -e '[.existing_ci[]] | any(endswith(".github/workflows/ci.yml"))' >/dev/null
}

@test "cog ci-detect --help dispatches" {
  run cog ci-detect --help

  assert_success
  [[ $output == *"Detect the CI target"* ]]
}
