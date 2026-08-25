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

@test "cog license-apply --list enumerates shipped SPDX ids" {
  run cog license-apply --list --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .mode == "list" and (.spdx_ids | index("mit")) and (.spdx_ids | index("apache-2.0")) and (.spdx_ids | index("bsd-3-clause")) and (.spdx_ids | index("gpl-3.0"))' >/dev/null
}

@test "cog license-apply mit substitutes holder and year" {
  run cog license-apply --project-root "${BATS_TEST_TMPDIR}/repo" --spdx mit --holder "Jane Doe" --year 2026 --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .spdx == "mit"' >/dev/null
  [ -f "${BATS_TEST_TMPDIR}/repo/LICENSE" ]
  grep -qF 'Copyright (c) 2026 Jane Doe' "${BATS_TEST_TMPDIR}/repo/LICENSE"
  run ! grep -qF '{{HOLDER}}' "${BATS_TEST_TMPDIR}/repo/LICENSE"
  run ! grep -qF '{{YEAR}}' "${BATS_TEST_TMPDIR}/repo/LICENSE"
}

@test "cog license-apply rejects an unknown SPDX id" {
  run --separate-stderr cog license-apply --project-root "${BATS_TEST_TMPDIR}/repo" --spdx bogus --holder x --year 2026 --json

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and (.reason | test("unknown spdx"))' >/dev/null
}

@test "cog license-apply requires holder and year for mit" {
  run --separate-stderr cog license-apply --project-root "${BATS_TEST_TMPDIR}/repo" --spdx mit --json

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and (.reason | test("requires --holder and --year"))' >/dev/null
}

@test "cog license-apply apache-2.0 ships verbatim without required fields" {
  run cog license-apply --project-root "${BATS_TEST_TMPDIR}/repo" --spdx apache-2.0 --json

  assert_success
  [ -f "${BATS_TEST_TMPDIR}/repo/LICENSE" ]
  grep -qF 'Apache License' "${BATS_TEST_TMPDIR}/repo/LICENSE"
  printf '%s\n' "$output" | jq -e '.ok == true and .spdx == "apache-2.0"' >/dev/null
}

@test "cog license-apply aborts on conflict" {
  touch "${BATS_TEST_TMPDIR}/repo/LICENSE"

  run --separate-stderr cog license-apply --project-root "${BATS_TEST_TMPDIR}/repo" --spdx mit --holder x --year 2026 --json

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and .reason == "destination conflict"' >/dev/null
}

@test "cog license-apply --help dispatches" {
  run cog license-apply --help

  assert_success
  [[ $output == *"Apply an SPDX LICENSE"* ]]
}

@test "cog license-apply --filename lands a dual-license half" {
  run cog license-apply --project-root "${BATS_TEST_TMPDIR}/repo" --spdx mit \
    --holder "Jane Doe" --year 2026 --filename LICENSE-MIT --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .filename == "LICENSE-MIT"' >/dev/null
  [ -f "${BATS_TEST_TMPDIR}/repo/LICENSE-MIT" ]
  [ ! -e "${BATS_TEST_TMPDIR}/repo/LICENSE" ]
  grep -qF 'Copyright (c) 2026 Jane Doe' "${BATS_TEST_TMPDIR}/repo/LICENSE-MIT"

  run cog license-apply --project-root "${BATS_TEST_TMPDIR}/repo" --spdx apache-2.0 \
    --filename LICENSE-APACHE --json

  assert_success
  [ -f "${BATS_TEST_TMPDIR}/repo/LICENSE-APACHE" ]
}

@test "cog license-apply rejects a filename that is not a license basename" {
  run --separate-stderr cog license-apply --project-root "${BATS_TEST_TMPDIR}/repo" \
    --spdx mit --holder x --year 2026 --filename src/notice.txt --json

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and (.reason | test("conventional license basename"))' >/dev/null
  [ ! -e "${BATS_TEST_TMPDIR}/repo/src/notice.txt" ]
}

@test "cog license-apply keeps an ampersand in the holder literal" {
  # Bash's patsub_replacement expands an unquoted `&` in a replacement to the
  # matched text, which would land `Smith {{HOLDER}} Wesson` in a real LICENSE
  # and report success.
  run cog license-apply --project-root "${BATS_TEST_TMPDIR}/repo" --spdx mit \
    --holder "Smith & Wesson" --year 2026 --json

  assert_success
  grep -qF 'Copyright (c) 2026 Smith & Wesson' "${BATS_TEST_TMPDIR}/repo/LICENSE"
  run ! grep -qF '{{' "${BATS_TEST_TMPDIR}/repo/LICENSE"
}
