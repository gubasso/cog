setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export COG_RESEARCH_SHELF_ROOT="${BATS_TEST_TMPDIR}/research-shelf"
}

sample_source_json() {
  printf '%s\n' '{"title":"Codex changelog","url":"https://developers.openai.com/codex/changelog","publisher":"OpenAI","access-date":"2026-06-20"}'
}

record_sample_entry() {
  local id="${1:-rs-test-entry}"

  run cog research-shelf record \
    --id "$id" \
    --recorded-date 2026-06-20 \
    --topic-tags "models,codex" \
    --source-json "$(sample_source_json)" \
    --summary "Codex CLI release notes are the primary source for current CLI availability." \
    --revalidate-after 2026-09-20 \
    --consuming-skills "openai-docs,plan-writer"
}

@test "cog research-shelf init creates shelf dir and index" {
  run --separate-stderr cog research-shelf init

  assert_success
  [ -z "$stderr" ]
  [[ $output == *"RESHELF_INIT_OK"* ]]
  [ -d "$COG_RESEARCH_SHELF_ROOT" ]
  [ -f "${COG_RESEARCH_SHELF_ROOT}/index.jsonl" ]
}

@test "cog research-shelf record appends a dated sourced entry" {
  run cog research-shelf init
  assert_success

  run cog research-shelf record \
    --recorded-date 2026-06-20 \
    --topic-tags "models,codex" \
    --source-json "$(sample_source_json)" \
    --summary "Codex CLI release notes are the primary source for current CLI availability." \
    --revalidate-after 2026-09-20 \
    --consuming-skills "openai-docs,plan-writer"

  assert_success
  assert_line --regexp '^RESHELF_ID=rs-20260620-[0-9a-f]{8}$'
  [ "$(wc -l <"${COG_RESEARCH_SHELF_ROOT}/index.jsonl")" -eq 1 ]
  jq -e '
    .id != "" and
    ."recorded-date" == "2026-06-20" and
    (."topic-tags" | length == 2) and
    (.sources | length == 1) and
    ."revalidate-after" == "2026-09-20" and
    (."consuming-skills" | length == 2)
  ' "${COG_RESEARCH_SHELF_ROOT}/index.jsonl" >/dev/null
}

@test "cog research-shelf list and get read the recorded entry" {
  run cog research-shelf init
  assert_success
  record_sample_entry rs-test-entry
  assert_success

  run cog research-shelf list
  assert_success
  assert_line "RESHELF_ID=rs-test-entry"

  run cog research-shelf get rs-test-entry
  assert_success
  printf '%s\n' "$output" | jq -e '
    .id == "rs-test-entry" and
    ."stable-summary" == "Codex CLI release notes are the primary source for current CLI availability."
  ' >/dev/null
}

@test "cog research-shelf validate passes on a good shelf" {
  run cog research-shelf init
  assert_success
  record_sample_entry rs-test-entry
  assert_success

  run cog research-shelf validate
  assert_success
  assert_line "RESHELF_VALID"
}

@test "cog research-shelf validate fails on malformed jsonl" {
  run cog research-shelf init
  assert_success
  printf '%s\n' 'not-json' >>"${COG_RESEARCH_SHELF_ROOT}/index.jsonl"

  run --separate-stderr cog research-shelf validate

  assert_failure
  [[ $stderr == *"err.kind: InvalidInput"* ]]
}

@test "cog research-shelf record rejects a duplicate id even past a malformed line" {
  run cog research-shelf init
  assert_success

  record_sample_entry rs-dup-entry
  assert_success
  # A malformed line later in the index must NOT mask the existing duplicate id:
  # the record guard scans line-by-line and ignores unparseable lines.
  printf '%s\n' 'not-json' >>"${COG_RESEARCH_SHELF_ROOT}/index.jsonl"

  run --separate-stderr cog research-shelf record \
    --id rs-dup-entry \
    --recorded-date 2026-06-20 \
    --topic-tags "models,codex" \
    --source-json "$(sample_source_json)" \
    --summary "Codex CLI release notes are the primary source for current CLI availability." \
    --revalidate-after 2026-09-20 \
    --consuming-skills "openai-docs,plan-writer"

  assert_failure
  [[ $stderr == *"err.kind: InvalidInput"* ]]
  [[ $stderr == *"duplicate research shelf id"* ]]
}

@test "cog research-shelf validate fails on undated or unsourced entry" {
  run cog research-shelf init
  assert_success
  printf '%s\n' '{"id":"rs-bad"}' >"${COG_RESEARCH_SHELF_ROOT}/index.jsonl"

  run --separate-stderr cog research-shelf validate

  assert_failure
  [[ $stderr == *"err.kind: InvalidInput"* ]]
  [[ $stderr == *"schema failure"* ]]
}

@test "cog research-shelf get fails for missing id" {
  run cog research-shelf init
  assert_success

  run --separate-stderr cog research-shelf get rs-missing

  assert_failure
  [[ $stderr == *"err.kind: InputNotFound"* ]]
}

@test "cog --json research-shelf round-trips init record list get validate" {
  run cog --json research-shelf init
  assert_success
  printf '%s\n' "$output" | jq -e '.schema == "cog.research-shelf.v1" and .ok == true' >/dev/null

  run cog --json research-shelf record \
    --id rs-json-entry \
    --recorded-date 2026-06-20 \
    --topic-tags "models,codex" \
    --source-json "$(sample_source_json)" \
    --summary "Codex CLI release notes are the primary source for current CLI availability." \
    --revalidate-after 2026-09-20 \
    --consuming-skills "openai-docs,plan-writer"
  assert_success
  printf '%s\n' "$output" | jq -e '
    .schema == "cog.research-shelf.v1" and
    .ok == true and
    .entry.id == "rs-json-entry"
  ' >/dev/null

  run cog --json research-shelf list
  assert_success
  printf '%s\n' "$output" | jq -e '
    .schema == "cog.research-shelf.v1" and
    .ok == true and
    ([.entries[].id] | index("rs-json-entry"))
  ' >/dev/null

  run cog --json research-shelf get rs-json-entry
  assert_success
  printf '%s\n' "$output" | jq -e '
    .schema == "cog.research-shelf.v1" and
    .ok == true and
    .entry.id == "rs-json-entry"
  ' >/dev/null

  run cog --json research-shelf validate
  assert_success
  printf '%s\n' "$output" | jq -e '
    .schema == "cog.research-shelf.v1" and
    .ok == true and
    .entries == 1
  ' >/dev/null
}

@test "cog research-shelf honors --root override" {
  local alternate_root="${BATS_TEST_TMPDIR}/alternate-shelf"

  run cog research-shelf init --root "$alternate_root"

  assert_success
  [ -d "$alternate_root" ]
  [ -f "${alternate_root}/index.jsonl" ]
  [ ! -e "$COG_RESEARCH_SHELF_ROOT" ]
}

@test "cog research-shelf --help prints usage" {
  run cog research-shelf --help

  assert_success
  [[ $output == *"Usage: cog research-shelf"* ]]
}
