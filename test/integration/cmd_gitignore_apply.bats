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

@test "cog gitignore-apply copies the gitignore template with nix devshell lines" {
  run cog gitignore-apply --project-root "${BATS_TEST_TMPDIR}/repo" --type rust --json

  assert_success
  [ -f "${BATS_TEST_TMPDIR}/repo/.gitignore" ]
  grep -qxF '.direnv/' "${BATS_TEST_TMPDIR}/repo/.gitignore"
  grep -qxF '/result' "${BATS_TEST_TMPDIR}/repo/.gitignore"
  printf '%s\n' "$output" | jq -e '.ok == true and .mode == "copy" and ([.copied[].dst] | any(endswith("/.gitignore")))' >/dev/null
}

@test "cog gitignore-apply generic type carries nix devshell lines" {
  run cog gitignore-apply --project-root "${BATS_TEST_TMPDIR}/repo" --type generic --json

  assert_success
  grep -qxF '.direnv/' "${BATS_TEST_TMPDIR}/repo/.gitignore"
  grep -qxF '/result' "${BATS_TEST_TMPDIR}/repo/.gitignore"
}

@test "cog gitignore-apply aborts on conflict" {
  touch "${BATS_TEST_TMPDIR}/repo/.gitignore"

  run --separate-stderr cog gitignore-apply --project-root "${BATS_TEST_TMPDIR}/repo" --type rust --json

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and .reason == "destination conflict"' >/dev/null
}

@test "cog gitignore-apply skips an existing file under skip policy" {
  printf 'custom\n' >"${BATS_TEST_TMPDIR}/repo/.gitignore"

  run cog gitignore-apply --project-root "${BATS_TEST_TMPDIR}/repo" --type rust --conflict skip --json

  assert_success
  printf '%s\n' "$output" | jq -e '[.skipped[].dst] | any(endswith("/.gitignore"))' >/dev/null
  [ "$(cat "${BATS_TEST_TMPDIR}/repo/.gitignore")" = "custom" ]
}

@test "cog gitignore-apply append adds missing fragments without clobbering" {
  printf '# existing\n*.tmp\n' >"${BATS_TEST_TMPDIR}/repo/.gitignore"

  run cog gitignore-apply --project-root "${BATS_TEST_TMPDIR}/repo" --type rust --append --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .mode == "append" and (.appended | index("/result"))' >/dev/null
  grep -qxF '*.tmp' "${BATS_TEST_TMPDIR}/repo/.gitignore"
  grep -qxF '.direnv/' "${BATS_TEST_TMPDIR}/repo/.gitignore"
  grep -qxF '/result' "${BATS_TEST_TMPDIR}/repo/.gitignore"
}

@test "cog gitignore-apply append is idempotent" {
  printf '# existing\n*.tmp\n' >"${BATS_TEST_TMPDIR}/repo/.gitignore"
  cog gitignore-apply --project-root "${BATS_TEST_TMPDIR}/repo" --type rust --append --json >/dev/null

  run cog gitignore-apply --project-root "${BATS_TEST_TMPDIR}/repo" --type rust --append --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and (.appended | length) == 0' >/dev/null
}

@test "cog gitignore-apply append copies when no file exists" {
  run cog gitignore-apply --project-root "${BATS_TEST_TMPDIR}/repo" --type rust --append --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and ([.copied[].dst] | any(endswith("/.gitignore")))' >/dev/null
  grep -qxF '/result' "${BATS_TEST_TMPDIR}/repo/.gitignore"
}

@test "cog gitignore-apply nix fragment tops up an existing gitignore of any type" {
  printf '# existing\n*.tmp\n' >"${BATS_TEST_TMPDIR}/repo/.gitignore"

  run cog gitignore-apply --project-root "${BATS_TEST_TMPDIR}/repo" --type nix --append --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .mode == "append" and (.appended | index(".direnv/")) and (.appended | index("/result"))' >/dev/null
  grep -qxF '*.tmp' "${BATS_TEST_TMPDIR}/repo/.gitignore"
  grep -qxF '.direnv/' "${BATS_TEST_TMPDIR}/repo/.gitignore"
  grep -qxF '/result' "${BATS_TEST_TMPDIR}/repo/.gitignore"
}

@test "cog gitignore-apply nix fragment is idempotent" {
  printf '*.tmp\n' >"${BATS_TEST_TMPDIR}/repo/.gitignore"
  cog gitignore-apply --project-root "${BATS_TEST_TMPDIR}/repo" --type nix --append --json >/dev/null

  run cog gitignore-apply --project-root "${BATS_TEST_TMPDIR}/repo" --type nix --append --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and (.appended | length) == 0' >/dev/null
}

@test "cog gitignore-apply --help dispatches" {
  run cog gitignore-apply --help

  assert_success
  [[ $output == *"Apply a gitignore template"* ]]
}
