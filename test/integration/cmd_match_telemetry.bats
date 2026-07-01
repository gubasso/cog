setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export COG_TELEMETRY_ROOT="${BATS_TEST_TMPDIR}/telemetry"
  export XDG_DATA_HOME="${BATS_TEST_TMPDIR}/data"
}

@test "cog match-telemetry --help dispatches" {
  run cog match-telemetry --help
  assert_success
  [[ $output == *"match-telemetry record"* ]]
}

@test "cog match-telemetry path resolves the global stream regardless of plan-store mode" {
  run cog match-telemetry path --json
  assert_success
  [[ "$(jq -r '.stream' <<<"$output")" == "${BATS_TEST_TMPDIR}/telemetry/match-outcomes.jsonl" ]]
}

@test "cog match-telemetry records prediction and outcome round-trips" {
  run cog match-telemetry record --kind prediction --project-key pk --plan-slug p --round-id setup \
    --requirement-ids "R1,R2" --predicted-executor executor-prex --score 31 --grade "Very High" --json
  assert_success
  [[ "$(jq -r '.record.kind' <<<"$output")" == "prediction" ]]

  run cog match-telemetry record --kind outcome --project-key pk --plan-slug p --round-id setup \
    --actual-executor executor-prex --result pass --review-loop-findings 0 --loc-changed 12 --files 2 --json
  assert_success
  [[ "$(jq -r '.record.review_loop_findings' <<<"$output")" == "0" ]]

  run cog match-telemetry validate --json
  assert_success
  [[ "$(jq -r '.entries' <<<"$output")" == "2" ]]
}

@test "cog match-telemetry report labels over/under/well-matched" {
  cog match-telemetry record --kind prediction --project-key pk --plan-slug p --round-id over \
    --predicted-executor executor-prex --score 31 --grade "Very High" --json >/dev/null
  cog match-telemetry record --kind outcome --project-key pk --plan-slug p --round-id over \
    --actual-executor executor-prex --result pass --review-loop-findings 0 --json >/dev/null
  cog match-telemetry record --kind prediction --project-key pk --plan-slug p --round-id well \
    --predicted-executor executor-vetted --score 12 --grade Moderate --json >/dev/null
  cog match-telemetry record --kind outcome --project-key pk --plan-slug p --round-id well \
    --actual-executor executor-vetted --result pass --cross-engine-deltas 3 --json >/dev/null
  cog match-telemetry record --kind prediction --project-key pk --plan-slug p --round-id under \
    --predicted-executor executor-oneshot --score 3 --json >/dev/null
  cog match-telemetry record --kind outcome --project-key pk --plan-slug p --round-id under \
    --actual-executor executor-oneshot --result fail --reverted --json >/dev/null

  run cog match-telemetry report --json
  assert_success
  [[ "$(jq -r '.rollup["over-powered"]' <<<"$output")" == "1" ]]
  [[ "$(jq -r '.rollup["well-matched"]' <<<"$output")" == "1" ]]
  [[ "$(jq -r '.rollup["under-powered"]' <<<"$output")" == "1" ]]
}

@test "cog match-telemetry validate fails closed on a malformed line" {
  cog match-telemetry record --kind prediction --project-key pk --plan-slug p --round-id x \
    --predicted-executor executor-prex --score 5 --json >/dev/null
  printf 'not json\n' >>"${BATS_TEST_TMPDIR}/telemetry/match-outcomes.jsonl"
  run cog match-telemetry validate --json
  assert_failure
  [[ "$(jq -r '.errors[0].reason' <<<"$output")" == *"malformed"* ]]
}

@test "cog match-telemetry round-key resolves a queued round file" {
  proj="${BATS_TEST_TMPDIR}/proj"
  mkdir -p "$proj"
  git -C "$proj" init -q
  git -C "$proj" remote add origin https://example.com/proj.git
  plan_dir="$(cd "$proj" && cog plan new --title "Demo" --global --json | jq -r '.plan_dir')"
  mkdir -p "$plan_dir/rounds"
  cat >"$plan_dir/rounds/setup-foo.md" <<'EOF'
# Setup Foo
## Acceptance Criteria
- [ ] (R1) thing
EOF
  run bash -c "cd '$proj' && cog match-telemetry round-key --round-path '$plan_dir/rounds/setup-foo.md' --json"
  assert_success
  [[ "$(jq -r '.plan_slug' <<<"$output")" == "demo" ]]
  [[ "$(jq -r '.round_id' <<<"$output")" == "setup-foo" ]]
  [[ "$(jq -r '.requirement_ids[0]' <<<"$output")" == "R1" ]]
}
