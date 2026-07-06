setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export LIB_DIR="${BATS_TEST_DIRNAME}/../../lib"
  source "${LIB_DIR}/helpers.sh"
  source "${LIB_DIR}/functions/fn_ui_print.sh"
  source "${LIB_DIR}/functions/fn_log.sh"
  source "${LIB_DIR}/functions/fn_error_raise.sh"
  source "${LIB_DIR}/functions/fn_json_write.sh"
  source "${LIB_DIR}/functions/fn_plan_complexity.sh"
  source "${LIB_DIR}/functions/fn_round_req.sh"
  source "${LIB_DIR}/functions/fn_round_split.sh"
  source "${LIB_DIR}/functions/fn_round_rightsize.sh"
  source "${LIB_DIR}/commands/cmd_round_rightsize.sh"
  unset COG_PLAN_COMPLEXITY_CEILING
  T="${BATS_TEST_TMPDIR}"
  ST="${T}/rightsize.state.json"
}

_write_baseline() {
  cat >"${T}/full-plan-draft.md" <<'EOF'
# Draft

## Acceptance Criteria

- [ ] (R1) A fails closed.
- [ ] (R2) B is reversible.
- [ ] (R3) C is documented.
EOF
}

_write_children() {
  cat >"${T}/a.md" <<'EOF'
# A

## Acceptance Criteria

- [ ] (R1) A fails closed.
- [ ] (R2) B is reversible.
EOF
  cat >"${T}/b.md" <<'EOF'
# B

## Acceptance Criteria

- [ ] (R3) C is documented.
EOF
}

@test "init seeds exactly one parent round" {
  _write_baseline
  run cog::fn::round_rightsize::init "$ST" "${T}/full-plan-draft.md"
  assert_success
  printf '%s\n' "$output" | jq -e '(.queue|length)==1 and .queue[0].origin=="baseline" and .queue[0].status=="awaiting-grade" and .state=="open"' >/dev/null
}

@test "init fails closed on an unstamped baseline" {
  cat >"${T}/full-plan-draft.md" <<'EOF'
# Draft

## Acceptance Criteria

- [ ] A has no requirement tag.
EOF
  run cog::fn::round_rightsize::init "$ST" "${T}/full-plan-draft.md"
  assert_failure
  [[ $output == *"not stamped"* || $stderr == *"not stamped"* ]] || [[ $status -ne 0 ]]
}

@test "init fails closed on a missing baseline" {
  run cog::fn::round_rightsize::init "$ST" "${T}/nope.md"
  assert_failure
}

@test "init refuses to clobber a seeded state" {
  _write_baseline
  cog::fn::round_rightsize::init "$ST" "${T}/full-plan-draft.md" >/dev/null
  run cog::fn::round_rightsize::init "$ST" "${T}/full-plan-draft.md"
  assert_failure
}

@test "record-grade under ceiling marks final and never grows the queue" {
  _write_baseline
  cog::fn::round_rightsize::init "$ST" "${T}/full-plan-draft.md" >/dev/null
  run cog::fn::round_rightsize::record_grade "$ST" full-plan-draft Low 8 false ""
  assert_success
  printf '%s\n' "$output" | jq -e '.over==false and .status=="final"' >/dev/null
  jq -e '(.queue|length)==1' "$ST" >/dev/null
}

@test "record-grade Extreme splittable marks awaiting-split; not-splittable marks irreducible" {
  _write_baseline
  cog::fn::round_rightsize::init "$ST" "${T}/full-plan-draft.md" >/dev/null
  run cog::fn::round_rightsize::record_grade "$ST" full-plan-draft Extreme 31 true ""
  assert_success
  printf '%s\n' "$output" | jq -e '.over==true and .status=="awaiting-split"' >/dev/null

  # Fresh state for the not-splittable branch.
  rm -f "$ST"
  cog::fn::round_rightsize::init "$ST" "${T}/full-plan-draft.md" >/dev/null
  run cog::fn::round_rightsize::record_grade "$ST" full-plan-draft Extreme 31 false ""
  assert_success
  printf '%s\n' "$output" | jq -e '.status=="irreducible-over-ceiling"' >/dev/null
}

@test "record-split with a covering pair grows the queue by exactly two" {
  _write_baseline
  _write_children
  cog::fn::round_rightsize::init "$ST" "${T}/full-plan-draft.md" >/dev/null
  cog::fn::round_rightsize::record_grade "$ST" full-plan-draft Extreme 31 true "" >/dev/null
  run cog::fn::round_rightsize::record_split "$ST" full-plan-draft true "${T}/a.md" "${T}/b.md"
  assert_success
  printf '%s\n' "$output" | jq -e '.ok==true and (.enqueued|length)==2' >/dev/null
  jq -e '(.queue|length)==3 and (.queue[0].status=="split") and ([.queue[]|select(.origin=="split-child")]|length)==2' "$ST" >/dev/null
}

@test "record-split with a lossy pair fails closed and leaves the queue unchanged" {
  _write_baseline
  cat >"${T}/a.md" <<'EOF'
# A

## Acceptance Criteria

- [ ] (R1) A fails closed.
EOF
  cat >"${T}/lossy.md" <<'EOF'
# Lossy

## Acceptance Criteria

- [ ] (R2) B is reversible.
EOF
  cog::fn::round_rightsize::init "$ST" "${T}/full-plan-draft.md" >/dev/null
  cog::fn::round_rightsize::record_grade "$ST" full-plan-draft Extreme 31 true "" >/dev/null
  # The command layer maps ok:false to EX_DATAERR.
  run cog::cmd::round_rightsize record-split --state "$ST" --round-id full-plan-draft \
    --split-performed true --child "${T}/a.md" --child "${T}/lossy.md" --json
  assert_failure
  printf '%s\n' "$output" | jq -e '.ok==false and (.coverage.lost|index("R3")|not|not)' >/dev/null
  jq -e '(.queue|length)==1 and .queue[0].status=="awaiting-split"' "$ST" >/dev/null
}

@test "record-split rejects a non-binary child count" {
  _write_baseline
  _write_children
  cog::fn::round_rightsize::init "$ST" "${T}/full-plan-draft.md" >/dev/null
  cog::fn::round_rightsize::record_grade "$ST" full-plan-draft Extreme 31 true "" >/dev/null
  run cog::fn::round_rightsize::record_split "$ST" full-plan-draft true "${T}/a.md" ""
  assert_failure
}

@test "record-split split-performed false marks irreducible without enqueue" {
  _write_baseline
  cog::fn::round_rightsize::init "$ST" "${T}/full-plan-draft.md" >/dev/null
  cog::fn::round_rightsize::record_grade "$ST" full-plan-draft Extreme 31 true "" >/dev/null
  run cog::fn::round_rightsize::record_split "$ST" full-plan-draft false "" ""
  assert_success
  jq -e '(.queue|length)==1 and .queue[0].status=="irreducible-over-ceiling"' "$ST" >/dev/null
}

@test "reopen flips a final round back to awaiting-split" {
  _write_baseline
  cog::fn::round_rightsize::init "$ST" "${T}/full-plan-draft.md" >/dev/null
  cog::fn::round_rightsize::record_grade "$ST" full-plan-draft Low 8 false "" >/dev/null
  run cog::fn::round_rightsize::reopen "$ST" full-plan-draft executor-reserved
  assert_success
  printf '%s\n' "$output" | jq -e '.queue[0].status=="awaiting-split" and .queue[0].reopened_for=="executor-reserved"' >/dev/null
}

@test "finalize fails closed when the queue is not terminal" {
  _write_baseline
  _write_children
  cog::fn::round_rightsize::init "$ST" "${T}/full-plan-draft.md" >/dev/null
  cog::fn::round_rightsize::record_grade "$ST" full-plan-draft Extreme 31 true "" >/dev/null
  cog::fn::round_rightsize::record_split "$ST" full-plan-draft true "${T}/a.md" "${T}/b.md" >/dev/null
  run cog::fn::round_rightsize::finalize_json "$ST"
  assert_failure
}

@test "finalize returns the final rounds with retained grade and score once terminal" {
  _write_baseline
  _write_children
  cog::fn::round_rightsize::init "$ST" "${T}/full-plan-draft.md" >/dev/null
  cog::fn::round_rightsize::record_grade "$ST" full-plan-draft Extreme 31 true "" >/dev/null
  cog::fn::round_rightsize::record_split "$ST" full-plan-draft true "${T}/a.md" "${T}/b.md" >/dev/null
  cog::fn::round_rightsize::record_grade "$ST" a Low 8 false "" >/dev/null
  cog::fn::round_rightsize::record_grade "$ST" b Low 6 false "" >/dev/null
  run cog::fn::round_rightsize::finalize_json "$ST"
  assert_success
  printf '%s\n' "$output" | jq -e '.ok==true and .coverage_ok==true and (.final_rounds|length)==2 and (.final_rounds|map(.grade)|all(.=="Low")) and (.final_rounds|map(.score)|sort==[6,8])' >/dev/null
  jq -e '.state=="finalized"' "$ST" >/dev/null
}

@test "record-grade is an idempotent replay on identical inputs and conflicts otherwise" {
  _write_baseline
  cog::fn::round_rightsize::init "$ST" "${T}/full-plan-draft.md" >/dev/null
  cog::fn::round_rightsize::record_grade "$ST" full-plan-draft Low 8 false "" >/dev/null
  run cog::fn::round_rightsize::record_grade "$ST" full-plan-draft Low 8 false ""
  assert_success
  printf '%s\n' "$output" | jq -e '.status=="final"' >/dev/null
  run cog::fn::round_rightsize::record_grade "$ST" full-plan-draft High 20 true ""
  assert_failure
}
