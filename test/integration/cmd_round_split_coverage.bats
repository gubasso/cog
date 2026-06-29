setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
}

@test "cog round-split --help dispatches" {
  run cog round-split --help
  assert_success
  [[ $output == *"Check split-round requirement coverage"* ]]
}

@test "cog round-split coverage checks id and text fallback" {
  cat >"${BATS_TEST_TMPDIR}/parent.md" <<'EOF'
# Parent

## Acceptance Criteria

- [ ] (R1) Keep.
- [ ] (R2) Share.
EOF
  cat >"${BATS_TEST_TMPDIR}/a.md" <<'EOF'
# A

## Acceptance Criteria

- [ ] (R1) Keep.
- [ ] (R2) Share.
EOF
  cat >"${BATS_TEST_TMPDIR}/b.md" <<'EOF'
# B

## Acceptance Criteria

- [ ] (R2) Share.
- [ ] (R3) Added.
EOF
  run cog round-split coverage --parent "${BATS_TEST_TMPDIR}/parent.md" --children "${BATS_TEST_TMPDIR}/a.md" "${BATS_TEST_TMPDIR}/b.md" --json
  assert_success
  printf '%s\n' "$output" | jq -e '.key == "id" and .lost == [] and (.duplicated | index("R2")) and (.added | index("R3"))' >/dev/null

  cat >"${BATS_TEST_TMPDIR}/text-parent.md" <<'EOF'
# Parent

## Acceptance Criteria

- [ ] Carry text.
EOF
  cat >"${BATS_TEST_TMPDIR}/text-child.md" <<'EOF'
# Child

## Acceptance Criteria

- [ ] Carry text.
EOF
  run cog round-split coverage --parent "${BATS_TEST_TMPDIR}/text-parent.md" --children "${BATS_TEST_TMPDIR}/text-child.md" --json
  assert_success
  printf '%s\n' "$output" | jq -e '.key == "text" and .coverage_ok == true' >/dev/null
}

@test "cog round-split coverage fails closed on loss" {
  cat >"${BATS_TEST_TMPDIR}/parent.md" <<'EOF'
# Parent

## Acceptance Criteria

- [ ] (R1) Keep.
- [ ] (R2) Lose.
EOF
  cat >"${BATS_TEST_TMPDIR}/child.md" <<'EOF'
# Child

## Acceptance Criteria

- [ ] (R1) Keep.
EOF
  run cog round-split coverage --parent "${BATS_TEST_TMPDIR}/parent.md" --children "${BATS_TEST_TMPDIR}/child.md" --json
  assert_failure 65
  printf '%s\n' "$output" | jq -e '.lost == ["R2"] and .coverage_ok == false' >/dev/null
}

@test "cog round-split coverage fails closed on invalid child even with no loss" {
  cat >"${BATS_TEST_TMPDIR}/parent.md" <<'EOF'
# Parent

## Acceptance Criteria

- [ ] (R1) Keep.
- [ ] (R2) Share.
EOF
  cat >"${BATS_TEST_TMPDIR}/child.md" <<'EOF'
# Child

## Acceptance Criteria

- [ ] (R1) Keep.
- [ ] (R2) Share.
- [ ] (R2) Duplicate within this child.
EOF
  run cog round-split coverage --parent "${BATS_TEST_TMPDIR}/parent.md" --children "${BATS_TEST_TMPDIR}/child.md" --json
  assert_failure 65
  printf '%s\n' "$output" | jq -e '.lost == [] and .ok == false and .coverage_ok == false' >/dev/null
}
