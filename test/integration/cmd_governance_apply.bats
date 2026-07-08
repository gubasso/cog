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

@test "cog governance-apply lands CLAUDE.md, AGENTS.md, and the ADR scaffold" {
  run cog governance-apply --project-root "${BATS_TEST_TMPDIR}/repo" --json

  assert_success
  [ -f "${BATS_TEST_TMPDIR}/repo/CLAUDE.md" ]
  [ -f "${BATS_TEST_TMPDIR}/repo/AGENTS.md" ]
  [ -f "${BATS_TEST_TMPDIR}/repo/docs/decisions/template.md" ]
  [ -f "${BATS_TEST_TMPDIR}/repo/docs/decisions/0001-self-containment.md" ]
  printf '%s\n' "$output" | jq -e '.ok == true and (.copied | length) == 4' >/dev/null
}

@test "cog governance-apply seeds the self-containment principle into AGENTS.md" {
  run cog governance-apply --project-root "${BATS_TEST_TMPDIR}/repo" --json

  assert_success
  grep -qF "self-contained" "${BATS_TEST_TMPDIR}/repo/AGENTS.md"
}

@test "cog governance-apply ships CLAUDE.md as a thin @AGENTS.md pointer" {
  run cog governance-apply --project-root "${BATS_TEST_TMPDIR}/repo" --json

  assert_success
  grep -qF "@AGENTS.md" "${BATS_TEST_TMPDIR}/repo/CLAUDE.md"
}

@test "cog governance-apply aborts on conflict" {
  printf '# keep\n' >"${BATS_TEST_TMPDIR}/repo/CLAUDE.md"

  run --separate-stderr cog governance-apply --project-root "${BATS_TEST_TMPDIR}/repo" --json

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and .reason == "destination conflict"' >/dev/null
}

@test "cog governance-apply skips an existing file under skip policy" {
  printf '# keep\n' >"${BATS_TEST_TMPDIR}/repo/CLAUDE.md"

  run cog governance-apply --project-root "${BATS_TEST_TMPDIR}/repo" --conflict skip --json

  assert_success
  printf '%s\n' "$output" | jq -e '[.skipped[].dst] | any(endswith("/CLAUDE.md"))' >/dev/null
  [ "$(cat "${BATS_TEST_TMPDIR}/repo/CLAUDE.md")" = "# keep" ]
}

@test "cog governance-apply rejects an invalid conflict policy" {
  run --separate-stderr cog governance-apply --project-root "${BATS_TEST_TMPDIR}/repo" --conflict clobber --json

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and (.reason | startswith("conflict policy"))' >/dev/null
}

@test "cog governance-apply fails on a bad project root" {
  run --separate-stderr cog governance-apply --project-root "${BATS_TEST_TMPDIR}/nope" --json

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and .reason == "project root is not a directory"' >/dev/null
}

@test "cog governance-apply --help dispatches" {
  run cog governance-apply --help

  assert_success
  [[ $output == *"Apply project governance docs"* ]]
}
