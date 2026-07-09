setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_DATA_HOME="${BATS_TEST_TMPDIR}/data"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  # Isolate from any system/global identity so "unset" cases are deterministic.
  export GIT_CONFIG_NOSYSTEM=1
  unset RUN_DIR REFACTOR_GUIDELINE
  mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"
  REPO="${BATS_TEST_TMPDIR}/repo"
  git init -q "$REPO"
}

@test "cog git-identity check reports a fully configured local identity" {
  git -C "$REPO" config user.name "Local Dev"
  git -C "$REPO" config user.email "local@example.com"

  run cog git-identity check --project-root "$REPO" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .name == "Local Dev" and .email == "local@example.com" and .author_string == "Local Dev <local@example.com>" and .name_source == "local" and .email_source == "local" and (.missing | length) == 0' >/dev/null
}

@test "cog git-identity check fails closed when user.email is unset" {
  git -C "$REPO" config user.name "Local Dev"

  run cog git-identity check --project-root "$REPO" --json

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and .email == null and .author_string == null and (.missing == ["user.email"]) and (.reason | test("user.email"))' >/dev/null
}

@test "cog git-identity check reports both keys missing" {
  run cog git-identity check --project-root "$REPO" --json

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and .name == null and .email == null and (.missing == ["user.name", "user.email"])' >/dev/null
}

@test "cog git-identity check fails closed outside a git repository" {
  mkdir -p "${BATS_TEST_TMPDIR}/plain"

  run cog git-identity check --project-root "${BATS_TEST_TMPDIR}/plain" --json

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and .reason == "not a git repository"' >/dev/null
}

@test "cog git-identity check prefers the repo-local identity over global" {
  git config --global user.name "Global Dev"
  git config --global user.email "global@example.com"
  git -C "$REPO" config user.name "Local Dev"
  git -C "$REPO" config user.email "local@example.com"

  run cog git-identity check --project-root "$REPO" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.name == "Local Dev" and .email == "local@example.com" and .name_source == "local" and .email_source == "local"' >/dev/null
}

@test "cog git-identity check resolves a global identity when no local is set" {
  git config --global user.name "Global Dev"
  git config --global user.email "global@example.com"

  run cog git-identity check --project-root "$REPO" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .name == "Global Dev" and .email == "global@example.com" and .name_source == "global" and .email_source == "global"' >/dev/null
}

@test "cog git-identity --help dispatches" {
  run cog git-identity --help

  assert_success
  [[ $output == *"git-identity check"* ]]
}
