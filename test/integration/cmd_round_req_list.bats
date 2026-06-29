setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
}

@test "cog round-req list emits criteria" {
  cat >"${BATS_TEST_TMPDIR}/alpha.md" <<'EOF'
# Alpha

## Acceptance Criteria

- [ ] (R1) First.
EOF
  run cog round-req list "${BATS_TEST_TMPDIR}/alpha.md" --json
  assert_success
  printf '%s\n' "$output" | jq -e '.stamped == true and .criteria[0].id == "R1"' >/dev/null
}
