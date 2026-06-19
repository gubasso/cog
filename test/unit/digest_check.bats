setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_DATA_HOME="${BATS_TEST_TMPDIR}/data"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "${BATS_TEST_TMPDIR}/digest"
}

write_clean_digest() {
  printf 'alpha\n' >"${BATS_TEST_TMPDIR}/digest/README.md"
  printf 'bravo\n' >"${BATS_TEST_TMPDIR}/digest/chapter.md"
  cat >"${BATS_TEST_TMPDIR}/digest/AGENTS.md" <<EOF
---
digest-of: .
last-synced: $(date +%F)
source-files:
  - README.md
  - chapter.md
token-estimate: 3
---

Body sentinel.
EOF
}

@test "digest-check clean digest passes" {
  write_clean_digest

  run cog digest-check --json "${BATS_TEST_TMPDIR}/digest/AGENTS.md"

  assert_success
  printf '%s\n' "$output" | jq -e '
    .schema == "cog.digest-check.v1"
    and .stale == false
    and (.drift.missing | length) == 0
    and (.drift.extra | length) == 0
    and (.drift.changed | length) == 0
    and .drift.token_estimate.changed == false
  ' >/dev/null
}

@test "digest-check reports extra source file" {
  write_clean_digest
  printf 'charlie\n' >"${BATS_TEST_TMPDIR}/digest/extra.md"

  run cog digest-check --json "${BATS_TEST_TMPDIR}/digest"

  assert_failure 65
  printf '%s\n' "$output" | jq -e '
    .stale == true
    and (.drift.extra == ["extra.md"])
  ' >/dev/null
}

@test "digest-check reports missing source file" {
  write_clean_digest
  rm "${BATS_TEST_TMPDIR}/digest/chapter.md"

  run cog digest-check --json "${BATS_TEST_TMPDIR}/digest/AGENTS.md"

  assert_failure 65
  printf '%s\n' "$output" | jq -e '
    .stale == true
    and (.drift.missing == ["chapter.md"])
  ' >/dev/null
}

@test "digest-check reports changed source file by mtime date" {
  printf 'alpha\n' >"${BATS_TEST_TMPDIR}/digest/README.md"
  touch -d '2026-06-19 00:00:00' "${BATS_TEST_TMPDIR}/digest/README.md"
  cat >"${BATS_TEST_TMPDIR}/digest/AGENTS.md" <<'EOF'
---
digest-of: .
last-synced: 2026-06-18
source-files:
  - README.md
token-estimate: 2
---

Body sentinel.
EOF

  run cog digest-check --json "${BATS_TEST_TMPDIR}/digest/AGENTS.md"

  assert_failure 65
  printf '%s\n' "$output" | jq -e '
    .stale == true
    and (.drift.changed == ["README.md"])
  ' >/dev/null
}

@test "digest-check ignores symlinked markdown files" {
  write_clean_digest
  ln -s README.md "${BATS_TEST_TMPDIR}/digest/linked.md"

  run cog digest-check --json "${BATS_TEST_TMPDIR}/digest/AGENTS.md"

  # Symlinks are not regular children, so they create no `extra` drift and the
  # digest stays clean.
  assert_success
  printf '%s\n' "$output" | jq -e '
    .stale == false
    and (.drift.extra | length) == 0
    and (.actual.source_files == ["README.md", "chapter.md"])
  ' >/dev/null
}

@test "digest-check reports token estimate mismatch" {
  write_clean_digest
  perl -0pi -e 's/token-estimate: 3/token-estimate: 99/' "${BATS_TEST_TMPDIR}/digest/AGENTS.md"

  run cog digest-check --json "${BATS_TEST_TMPDIR}/digest/AGENTS.md"

  assert_failure 65
  printf '%s\n' "$output" | jq -e '
    .schema == "cog.digest-check.v1"
    and .drift.token_estimate.changed == true
    and .drift.token_estimate.expected == 3
    and .drift.token_estimate.actual == 99
  ' >/dev/null
}
