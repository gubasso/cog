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

@test "cog nix-devshell-apply copies the generic flake and envrc" {
  run cog nix-devshell-apply --project-root "${BATS_TEST_TMPDIR}/repo" --type generic --json

  assert_success
  [ -f "${BATS_TEST_TMPDIR}/repo/flake.nix" ]
  [ -f "${BATS_TEST_TMPDIR}/repo/.envrc" ]
  grep -q 'use flake' "${BATS_TEST_TMPDIR}/repo/.envrc"
  printf '%s\n' "$output" | jq -e '.ok == true and ([.copied[].dst] | any(endswith("/flake.nix"))) and ([.copied[].dst] | any(endswith("/.envrc")))' >/dev/null
}

@test "cog nix-devshell-apply copies rust-toolchain.toml for the rust type" {
  run cog nix-devshell-apply --project-root "${BATS_TEST_TMPDIR}/repo" --type rust --json

  assert_success
  [ -f "${BATS_TEST_TMPDIR}/repo/rust-toolchain.toml" ]
  printf '%s\n' "$output" | jq -e '[.copied[].dst] | any(endswith("/rust-toolchain.toml"))' >/dev/null
}

@test "cog nix-devshell-apply layers the poetry venv in the python envrc" {
  run cog nix-devshell-apply --project-root "${BATS_TEST_TMPDIR}/repo" --type python --json

  assert_success
  grep -q 'POETRY_ACTIVE' "${BATS_TEST_TMPDIR}/repo/.envrc"
}

@test "cog nix-devshell-apply aborts on a flake conflict without overwriting" {
  printf 'existing\n' >"${BATS_TEST_TMPDIR}/repo/flake.nix"

  run --separate-stderr cog nix-devshell-apply --project-root "${BATS_TEST_TMPDIR}/repo" --type generic --flake-conflict abort --json

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and .reason == "destination conflict"' >/dev/null
  [ "$(cat "${BATS_TEST_TMPDIR}/repo/flake.nix")" = "existing" ]
}

@test "cog nix-devshell-apply honors per-file conflict policies" {
  printf 'root=keep\n' >"${BATS_TEST_TMPDIR}/repo/.envrc"

  run cog nix-devshell-apply --project-root "${BATS_TEST_TMPDIR}/repo" --type generic --envrc-conflict skip --flake-conflict overwrite --json

  assert_success
  printf '%s\n' "$output" | jq -e '([.skipped[].dst] | any(endswith("/.envrc"))) and ([.copied[].dst] | any(endswith("/flake.nix")))' >/dev/null
  [ "$(cat "${BATS_TEST_TMPDIR}/repo/.envrc")" = "root=keep" ]
}

@test "cog nix-devshell-apply rejects an invalid conflict policy" {
  run --separate-stderr cog nix-devshell-apply --project-root "${BATS_TEST_TMPDIR}/repo" --type generic --flake-conflict bogus --json

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false' >/dev/null
}

@test "cog nix-devshell-apply --help dispatches" {
  run cog nix-devshell-apply --help

  assert_success
  [[ $output == *"Apply a nix devshell template"* ]]
}
