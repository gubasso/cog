setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  mkdir -p "$HOME" "$XDG_STATE_HOME"
  unset COG_PLAN_COMPLEXITY_CEILING
  T="${BATS_TEST_TMPDIR}"
  ST="${T}/rightsize.state.json"
  cat >"${T}/full-plan-draft.md" <<'EOF'
# Draft

## Acceptance Criteria

- [ ] (R1) A fails closed.
- [ ] (R2) B is reversible.
- [ ] (R3) C is documented.
EOF
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

_valid_state() {
  jq -e '(.schema=="cog.round-rightsize.v1") and (.state|type=="string") and (.queue|type=="array")' "$ST" >/dev/null
}

@test "round-rightsize drives a full seed -> split -> finalize loop" {
  run cog round-rightsize init --state "$ST" --baseline "${T}/full-plan-draft.md" --json
  assert_success
  printf '%s\n' "$output" | jq -e '(.queue|length)==1' >/dev/null
  _valid_state

  run cog round-rightsize pending --state "$ST" --json
  assert_success
  printf '%s\n' "$output" | jq -e '.terminal==false and (.awaiting_grade|length)==1' >/dev/null

  run cog round-rightsize record-grade --state "$ST" --round-id full-plan-draft \
    --grade Extreme --score 31 --splittable true --json
  assert_success
  printf '%s\n' "$output" | jq -e '.status=="awaiting-split"' >/dev/null
  _valid_state

  run cog round-rightsize record-split --state "$ST" --round-id full-plan-draft \
    --split-performed true --child "${T}/a.md" --child "${T}/b.md" --json
  assert_success
  printf '%s\n' "$output" | jq -e '(.enqueued|length)==2' >/dev/null
  _valid_state

  run cog round-rightsize pending --state "$ST" --json
  assert_success
  printf '%s\n' "$output" | jq -e '.terminal==false and (.awaiting_grade|length)==2' >/dev/null

  run cog round-rightsize record-grade --state "$ST" --round-id a \
    --grade Low --score 8 --splittable false --json
  assert_success
  run cog round-rightsize record-grade --state "$ST" --round-id b \
    --grade Moderate --score 12 --splittable false --json
  assert_success

  run cog round-rightsize pending --state "$ST" --json
  assert_success
  printf '%s\n' "$output" | jq -e '.terminal==true' >/dev/null

  run cog round-rightsize finalize --state "$ST" --json
  assert_success
  printf '%s\n' "$output" | jq -e '.ok==true and .coverage_ok==true and (.final_rounds|length)==2' >/dev/null
  _valid_state
  jq -e '.state=="finalized"' "$ST" >/dev/null
}

@test "round-rightsize record-split fails closed with EX_DATAERR on a lossy split" {
  cat >"${T}/lossy.md" <<'EOF'
# Lossy

## Acceptance Criteria

- [ ] (R1) A fails closed.
EOF
  cog round-rightsize init --state "$ST" --baseline "${T}/full-plan-draft.md" --json >/dev/null
  cog round-rightsize record-grade --state "$ST" --round-id full-plan-draft \
    --grade Extreme --score 31 --splittable true --json >/dev/null
  run cog round-rightsize record-split --state "$ST" --round-id full-plan-draft \
    --split-performed true --child "${T}/a.md" --child "${T}/lossy.md" --json
  assert_failure
  [[ $status -eq 65 ]]
  printf '%s\n' "$output" | jq -e '.ok==false' >/dev/null
  jq -e '(.queue|length)==1 and .queue[0].status=="awaiting-split"' "$ST" >/dev/null
}

@test "round-rightsize init fails closed on an unstamped baseline" {
  cat >"${T}/unstamped.md" <<'EOF'
# Draft

## Acceptance Criteria

- [ ] No requirement tag here.
EOF
  run cog round-rightsize init --state "$ST" --baseline "${T}/unstamped.md" --json
  assert_failure
}
