setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
}

@test "cog round-req --help dispatches" {
  run cog round-req --help
  assert_success
  [[ $output == *"Stamp and list round acceptance requirement IDs"* ]]
}

@test "cog round-req stamp is monotonic and idempotent" {
  cat >"${BATS_TEST_TMPDIR}/alpha.md" <<'EOF'
# Alpha

## Acceptance Criteria

- [ ] First.
- [ ] This plan's `queue-rounds.yaml` shows round `alpha` as `done`. {{If this is the final implementation-plan round, also mark the plan done.}}
- [ ] The top-level .implementation-plans/queue-plans.yaml shows this plan as done.
EOF
  cat >"${BATS_TEST_TMPDIR}/beta.md" <<'EOF'
# Beta

## Acceptance Criteria

- [ ] (R5) Existing.
- [ ] Second.
EOF
  run cog round-req stamp "${BATS_TEST_TMPDIR}" --json
  assert_success
  printf '%s\n' "$output" | jq -e '.plan_max_before == 5 and (.assigned | length == 2) and ([.assigned[].id] == ["R6","R7"])' >/dev/null

  run cog round-req stamp "${BATS_TEST_TMPDIR}" --json
  assert_success
  printf '%s\n' "$output" | jq -e '.assigned == [] and .wrote == false' >/dev/null
}
