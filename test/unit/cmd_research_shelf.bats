setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export LIB_DIR="${BATS_TEST_DIRNAME}/../../lib"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_DATA_HOME="${BATS_TEST_TMPDIR}/xdg"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  mkdir -p "$HOME" "$XDG_STATE_HOME" "$XDG_DATA_HOME"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/helpers.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_ui_print.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_log.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_error_raise.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_json_write.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_data.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_research.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/commands/cmd_research_shelf.sh"
  export COG_RESEARCH_SHELF_ROOT="${BATS_TEST_TMPDIR}/shelf"
  mkdir -p "$COG_RESEARCH_SHELF_ROOT"
}

# Write an index whose total size is above the per-argument kernel cap, so any
# form that routes the entries through argv fails. Linux caps ONE argv string at
# MAX_ARG_STRLEN (128KiB) while macOS caps only the ~1MB total, so the payload
# clears both: 6 records with a 256KiB summary each is about 1.5MB. Few fat
# records rather than many small ones keeps the test fast, because validate
# spawns three jq processes per line. printf is a builtin, so building the
# fixture does not itself hit the cap the fixture exists to exceed.
write_oversized_shelf() {
  local pad i
  pad="$(head -c 262144 /dev/zero | tr '\0' 'x')"
  for i in 1 2 3 4 5 6; do
    printf '{"id":"rs-2026062%s","recorded-date":"2026-06-2%s","topic-tags":["models","bootstrap-template"],"sources":[{"title":"t","url":"https://example.test","publisher":"p","access-date":"2026-06-20"}],"stable-summary":"%s","revalidate-after":"2099-01-01","consuming-skills":["s"]}\n' \
      "$i" "$i" "$pad"
  done >"${COG_RESEARCH_SHELF_ROOT}/index.jsonl"
}

@test "research-shelf list survives an index above the argv limit" {
  write_oversized_shelf

  run cog::cmd::research_shelf list --json

  assert_success
  [ "$(jq -r '.entries | length' <<<"$output")" = "6" ]
  [ "$(jq -r '.entries[0].id' <<<"$output")" = "rs-20260621" ]
  [ "$(jq -r '.entries[5].id' <<<"$output")" = "rs-20260626" ]
}

@test "research-shelf validate reads an index above the argv limit" {
  write_oversized_shelf

  run cog::cmd::research_shelf validate --json

  assert_success
  [ "$(jq -r '.ok' <<<"$output")" = "true" ]
  [ "$(jq -r '.entries' <<<"$output")" = "6" ]
  [ "$(jq -r '.errors | length' <<<"$output")" = "0" ]
}

# A valid shelf accumulates no errors, so shelf size alone never reaches the
# argv path validate actually changed. The errors array does, and it grows two
# ways: with the number of bad lines, and with the length of one reason. A
# duplicate-id reason embeds the offending id, and the entry schema bounds an
# id's characters but not its length, so a few fat ids build a payload above the
# cap in a handful of lines. Many short bad lines would need thousands of them,
# and validate spawns a jq process per line.
write_duplicate_id_shelf() {
  local id line
  id="$(head -c 100000 /dev/zero | tr '\0' 'a')"
  line="$(printf '{"id":"%s","recorded-date":"2026-06-20","topic-tags":["t"],"sources":[{"title":"t","url":"https://example.test","publisher":"p","access-date":"2026-06-20"}],"stable-summary":"s","revalidate-after":"2030-01-01","consuming-skills":["s"]}' "$id")"
  local i
  for i in $(seq 1 12); do
    printf '%s\n' "$line"
  done >"${COG_RESEARCH_SHELF_ROOT}/index.jsonl"
}

@test "research-shelf validate survives an errors array above the argv limit" {
  write_duplicate_id_shelf

  run --separate-stderr cog::cmd::research_shelf validate --json

  assert_failure
  [ "$(jq -r '.ok' <<<"$output")" = "false" ]
  [ "$(jq -r '.entries' <<<"$output")" = "1" ]
  [ "$(jq -r '.errors | length' <<<"$output")" = "11" ]
  [ "$(jq -r '.errors | map(.reason | length) | add > 1000000' <<<"$output")" = "true" ]
  [ "$(jq -r '.errors[0].reason | startswith("duplicate id: ")' <<<"$output")" = "true" ]
}

@test "research-shelf validate reports one error per bad line" {
  {
    printf '%s\n' 'not-json'
    printf '%s\n' '{"id":"rs-x"}'
    printf '%s\n' ''
  } >"${COG_RESEARCH_SHELF_ROOT}/index.jsonl"

  run --separate-stderr cog::cmd::research_shelf validate --json

  assert_failure
  [ "$(jq -r '.ok' <<<"$output")" = "false" ]
  [ "$(jq -r '.errors | length' <<<"$output")" = "3" ]
  [ "$(jq -r '[.errors[].reason] | join(",")' <<<"$output")" = "malformed JSON,schema failure,blank line" ]
}

@test "research-shelf validate reports no errors for an empty index" {
  : >"${COG_RESEARCH_SHELF_ROOT}/index.jsonl"

  run cog::cmd::research_shelf validate --json

  assert_success
  [ "$(jq -r '.ok' <<<"$output")" = "true" ]
  [ "$(jq -r '.entries' <<<"$output")" = "0" ]
  [ "$(jq -c '.errors' <<<"$output")" = "[]" ]
}

@test "research-shelf list reports no entries for an empty index" {
  : >"${COG_RESEARCH_SHELF_ROOT}/index.jsonl"

  run cog::cmd::research_shelf list --json

  assert_success
  [ "$(jq -c '.entries' <<<"$output")" = "[]" ]
  [ "$(jq -r '.action' <<<"$output")" = "list" ]
}
