setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_DATA_HOME="${BATS_TEST_TMPDIR}/data"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "${BATS_TEST_TMPDIR}/digest"
}

write_stale_digest() {
  printf 'alpha\n' >"${BATS_TEST_TMPDIR}/digest/README.md"
  printf 'bravo\n' >"${BATS_TEST_TMPDIR}/digest/chapter.md"
  cat >"${BATS_TEST_TMPDIR}/digest/AGENTS.md" <<'EOF'
---
digest-of: .
last-synced: 2026-06-18
source-files:
  - README.md
token-estimate: 99
---

Body sentinel line 1.
Body sentinel line 2.
EOF
}

body_after_frontmatter() {
  awk '
    NR == 1 && $0 == "---" {
      in_fm = 1
      next
    }
    in_fm && $0 == "---" {
      in_fm = 0
      body = 1
      next
    }
    body {
      print
    }
  ' "$1"
}

@test "digest-stamp updates canonical frontmatter fields and preserves body" {
  write_stale_digest
  body_after_frontmatter "${BATS_TEST_TMPDIR}/digest/AGENTS.md" >"${BATS_TEST_TMPDIR}/before-body"

  run cog digest-stamp --json "${BATS_TEST_TMPDIR}/digest/AGENTS.md"

  assert_success
  printf '%s\n' "$output" | jq -e '
    .schema == "cog.digest-stamp.v1"
    and .changed == true
    and .after.last_synced == "'"$(date +%F)"'"
    and .after.source_files == ["README.md", "chapter.md"]
    and .after.token_estimate == 3
  ' >/dev/null
  body_after_frontmatter "${BATS_TEST_TMPDIR}/digest/AGENTS.md" >"${BATS_TEST_TMPDIR}/after-body"
  cmp "${BATS_TEST_TMPDIR}/before-body" "${BATS_TEST_TMPDIR}/after-body"
  grep -Fqx "last-synced: $(date +%F)" "${BATS_TEST_TMPDIR}/digest/AGENTS.md"
}

@test "digest-stamp is idempotent on second run" {
  write_stale_digest
  cog digest-stamp --json "${BATS_TEST_TMPDIR}/digest/AGENTS.md" >/dev/null
  cp "${BATS_TEST_TMPDIR}/digest/AGENTS.md" "${BATS_TEST_TMPDIR}/before"

  run cog digest-stamp --json "${BATS_TEST_TMPDIR}/digest/AGENTS.md"

  assert_success
  printf '%s\n' "$output" | jq -e '.changed == false' >/dev/null
  cmp "${BATS_TEST_TMPDIR}/before" "${BATS_TEST_TMPDIR}/digest/AGENTS.md"
}

@test "digest-stamp dry-run writes nothing" {
  write_stale_digest
  cp "${BATS_TEST_TMPDIR}/digest/AGENTS.md" "${BATS_TEST_TMPDIR}/before"
  find "${BATS_TEST_TMPDIR}/digest" -mindepth 1 -maxdepth 1 -printf '%f\n' | LC_ALL=C sort >"${BATS_TEST_TMPDIR}/dir-before"

  run cog digest-stamp --dry-run --json "${BATS_TEST_TMPDIR}/digest/AGENTS.md"

  assert_success
  printf '%s\n' "$output" | jq -e '
    .schema == "cog.digest-stamp.v1"
    and .dry_run == true
    and .changed == true
  ' >/dev/null
  cmp "${BATS_TEST_TMPDIR}/before" "${BATS_TEST_TMPDIR}/digest/AGENTS.md"
  # No stray temp files left in (or removed from) the digest directory.
  find "${BATS_TEST_TMPDIR}/digest" -mindepth 1 -maxdepth 1 -printf '%f\n' | LC_ALL=C sort >"${BATS_TEST_TMPDIR}/dir-after"
  cmp "${BATS_TEST_TMPDIR}/dir-before" "${BATS_TEST_TMPDIR}/dir-after"
}

@test "digest-stamp dry-run works in a read-only digest directory" {
  write_stale_digest
  cp "${BATS_TEST_TMPDIR}/digest/AGENTS.md" "${BATS_TEST_TMPDIR}/before"
  chmod a-w "${BATS_TEST_TMPDIR}/digest"

  run cog digest-stamp --dry-run --json "${BATS_TEST_TMPDIR}/digest/AGENTS.md"
  local status="$status"
  chmod u+w "${BATS_TEST_TMPDIR}/digest"

  [ "$status" -eq 0 ]
  cmp "${BATS_TEST_TMPDIR}/before" "${BATS_TEST_TMPDIR}/digest/AGENTS.md"
}

raw_body_slice() {
  # Emit the body bytes verbatim (everything after the closing '---' line),
  # preserving the exact trailing-newline count so a normalizing rewrite is caught.
  local file="$1" off
  off="$(grep -aob '^---$' "$file" | sed -n '2p' | cut -d: -f1)"
  tail -c "+$((off + 5))" "$file"
}

@test "digest-stamp preserves body bytes with no trailing newline" {
  printf 'alpha\n' >"${BATS_TEST_TMPDIR}/digest/README.md"
  printf -- '---\ndigest-of: .\nlast-synced: 2026-06-18\nsource-files:\n  - README.md\ntoken-estimate: 99\n---\nBody line.\nNo trailing newline.' \
    >"${BATS_TEST_TMPDIR}/digest/AGENTS.md"
  raw_body_slice "${BATS_TEST_TMPDIR}/digest/AGENTS.md" >"${BATS_TEST_TMPDIR}/before-body"

  run cog digest-stamp "${BATS_TEST_TMPDIR}/digest/AGENTS.md"

  assert_success
  raw_body_slice "${BATS_TEST_TMPDIR}/digest/AGENTS.md" >"${BATS_TEST_TMPDIR}/after-body"
  cmp "${BATS_TEST_TMPDIR}/before-body" "${BATS_TEST_TMPDIR}/after-body"
}

@test "digest-stamp preserves body bytes with multiple trailing newlines" {
  printf 'alpha\n' >"${BATS_TEST_TMPDIR}/digest/README.md"
  printf -- '---\ndigest-of: .\nlast-synced: 2026-06-18\nsource-files:\n  - README.md\ntoken-estimate: 99\n---\nBody.\n\n\n' \
    >"${BATS_TEST_TMPDIR}/digest/AGENTS.md"
  raw_body_slice "${BATS_TEST_TMPDIR}/digest/AGENTS.md" >"${BATS_TEST_TMPDIR}/before-body"

  run cog digest-stamp "${BATS_TEST_TMPDIR}/digest/AGENTS.md"

  assert_success
  raw_body_slice "${BATS_TEST_TMPDIR}/digest/AGENTS.md" >"${BATS_TEST_TMPDIR}/after-body"
  cmp "${BATS_TEST_TMPDIR}/before-body" "${BATS_TEST_TMPDIR}/after-body"
}

@test "digest-stamp directory argument resolves to AGENTS.md" {
  write_stale_digest

  run cog digest-stamp --json "${BATS_TEST_TMPDIR}/digest"

  assert_success
  printf '%s\n' "$output" | jq -e '
    .schema == "cog.digest-stamp.v1"
    and .digest_file == "'"${BATS_TEST_TMPDIR}"'/digest/AGENTS.md"
    and .changed == true
  ' >/dev/null
}
