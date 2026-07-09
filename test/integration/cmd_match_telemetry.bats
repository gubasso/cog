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

@test "cog match-telemetry records a v2 outcome with round_scope" {
  run cog match-telemetry record --kind outcome --project-key pk --plan-slug p --round-id rs \
    --actual-executor executor-prex --result pass --review-loop-findings 2 \
    --files 3 --loc-changed 40 --round-scope-max-files 3 --round-scope-max-lines 120 \
    --override-approval-gate --json
  assert_success
  printf '%s\n' "$output" | jq -e '
    .record.schema == "cog.match-telemetry.outcome.v2"
    and .record.round_scope.declared.max_files == 3
    and .record.round_scope.actual.files == 3
    and .record.round_scope.exceeded == false
    and .record.override_approval_gate == true
  ' >/dev/null
}

@test "cog match-telemetry report flags a small-scope high-grade round over-powered" {
  cog match-telemetry record --kind prediction --project-key pk --plan-slug p --round-id tiny \
    --predicted-executor executor-prex --score 28 --grade "Very High" --json >/dev/null
  cog match-telemetry record --kind outcome --project-key pk --plan-slug p --round-id tiny \
    --actual-executor executor-prex --result pass --review-loop-findings 1 \
    --files 3 --loc-changed 20 --json >/dev/null

  run cog match-telemetry report --json
  assert_success
  printf '%s\n' "$output" | jq -e '
    (.rows[] | select(.round_id == "tiny") | .match_quality) == "over-powered"
  ' >/dev/null
}

@test "cog match-telemetry report folds a fail-then-pass round into one logical round" {
  cog match-telemetry record --kind prediction --project-key pk --plan-slug p --round-id retry \
    --predicted-executor executor-prex --score 22 --json >/dev/null
  cog match-telemetry record --kind outcome --project-key pk --plan-slug p --round-id retry \
    --actual-executor executor-prex --result fail --review-loop-findings 0 --json >/dev/null
  sleep 1
  cog match-telemetry record --kind outcome --project-key pk --plan-slug p --round-id retry \
    --actual-executor executor-prex --result pass --review-loop-findings 3 --json >/dev/null

  run cog match-telemetry report --json
  assert_success
  printf '%s\n' "$output" | jq -e '
    .outcomes == 2 and .logical_rounds == 1
    and (.rows[] | select(.round_id == "retry") | .result == "pass" and .retries == 1 and .match_quality == "well-matched")
  ' >/dev/null
}

@test "cog match-telemetry recalibrate emits saturation flags" {
  cog match-telemetry record --kind outcome --project-key pk --plan-slug p --round-id a \
    --actual-executor executor-prex --result pass --review-loop-findings 3 --json >/dev/null

  run cog match-telemetry recalibrate --json
  assert_success
  printf '%s\n' "$output" | jq -e '
    (.saturation_flags[] | select(.executor == "executor-vetted") | .kind) == "zero-data"
    and (.by_executor[] | select(.executor == "executor-prex") | .outcomes) == 1
  ' >/dev/null
}
