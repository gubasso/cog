setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_DATA_HOME="${BATS_TEST_TMPDIR}/data"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  unset RUN_DIR DOCS_NOTES_REPO REFACTOR_GUIDELINE RIPTASK_REPO
  mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "${BATS_TEST_TMPDIR}/repo/scripts"
}

@test "cog claudemd-audit emits deterministic audit fields" {
  touch "${BATS_TEST_TMPDIR}/repo/scripts/build.sh"
  cat >"${BATS_TEST_TMPDIR}/repo/CLAUDE.md" <<'EOF'
# Project

See `scripts/build.sh` and `missing/file.txt`.

```
$ make test
```
EOF

  run cog claudemd-audit --path "${BATS_TEST_TMPDIR}/repo/CLAUDE.md" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .line_count == 7 and .estimated_tokens == 35 and (.lint.fenced_code_blocks_without_language | index(5))' >/dev/null
}

@test "cog claudemd-audit rejects unreadable files" {
  run --separate-stderr cog claudemd-audit --path "${BATS_TEST_TMPDIR}/missing.md" --json

  assert_failure
  [[ $stderr == *"err.kind: InputUnreadable"* ]]
}

@test "cog claudemd-audit --help dispatches" {
  run cog claudemd-audit --help

  assert_success
  [[ $output == *"Audit CLAUDE.md deterministic signals"* ]]
}
