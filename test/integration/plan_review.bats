setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  mkdir -p "$HOME" "$XDG_STATE_HOME"
  PLAN_INPUT="${BATS_TEST_TMPDIR}/input-plan.md"
  REQUEST_INPUT="${BATS_TEST_TMPDIR}/request.md"
  printf '%s\n' "# Plan" >"$PLAN_INPUT"
  printf '%s\n' "# Request" >"$REQUEST_INPUT"
}

write_review_and_plan() {
  REVIEW="${BATS_TEST_TMPDIR}/review.md"
  FOLDED="${BATS_TEST_TMPDIR}/folded.md"
  MANIFEST="${BATS_TEST_TMPDIR}/manifest.json"
  printf '# Annotated Plan Review\n\n## Verdict\n\nMODIFIED\n\n## Annotated Plan\n\n### APPROVED\n\n- Keep\n\n### MODIFIED\n\n- Change\n\n### REMOVED\n\n### ADDED\n\n- Add\n' >"$REVIEW"
  printf '# Folded\n\n## Goal\n\nG\n\n## Implementation Plan\n\n1. Do\n\n## Acceptance Criteria\n\n- [ ] Done\n' >"$FOLDED"
  jq -n '{schema:"cog.plan-review.fold-manifest.v1",dispositions:[{id:"A1",disposition:"folded"},{id:"M1",disposition:"waived",reason:"Superseded"},{id:"D1",disposition:"folded"}]}' >"$MANIFEST"
}

@test "cog plan-review --help prints usage" {
  run cog plan-review --help

  assert_success
  [[ $output == *"Usage: cog plan-review"* ]]
}

@test "cog plan-review save writes default runtime artifact" {
  run cog plan-review save --plan "$PLAN_INPUT" --request "$REQUEST_INPUT"

  assert_success
  assert_line --regexp '^PLAN_REVIEW_PATH=.*input-plan-md\.md$'
  local output_path="${output#PLAN_REVIEW_PATH=}"
  [[ $output_path == "$XDG_STATE_HOME"/cog/runs/plan-review-input-plan-md-*"/input-plan-md.md" ]]
  [ -f "$output_path" ]
}

@test "cog plan-review save writes user output path" {
  local out="${BATS_TEST_TMPDIR}/review/out.md"

  run cog plan-review save --plan "$PLAN_INPUT" --request "$REQUEST_INPUT" --output "$out"

  assert_success
  assert_output "PLAN_REVIEW_PATH=${out}"
  [ -f "$out" ]
}

@test "cog plan-review orchestrator writes requested output path" {
  local out="${BATS_TEST_TMPDIR}/review/orchestrator.md"

  run cog plan-review orchestrator "$PLAN_INPUT" "$REQUEST_INPUT" "$out"

  assert_success
  assert_output "PLAN_REVIEW_PATH=${out}"
  [ -f "$out" ]
}

@test "cog plan-review validate succeeds for generated artifact" {
  local out="${BATS_TEST_TMPDIR}/review.md"
  run cog plan-review orchestrator "$PLAN_INPUT" "$REQUEST_INPUT" "$out"
  assert_success

  run cog plan-review validate "$out"

  assert_success
  assert_output "PLAN_REVIEW_VALID"
}

@test "cog --json plan-review orchestrator emits schema action and ok" {
  local out="${BATS_TEST_TMPDIR}/review/json.md"

  run cog --json plan-review orchestrator "$PLAN_INPUT" "$REQUEST_INPUT" "$out"

  assert_success
  printf '%s\n' "$output" | jq -e '
    .schema == "cog.plan-review.v1" and .action == "orchestrator" and .ok == true
  ' >/dev/null
}

@test "cog plan-review rejects relative input paths" {
  run --separate-stderr cog plan-review save --plan relative.md --request "$REQUEST_INPUT"

  assert_failure
  [[ $stderr == *"err.kind: InvalidInput"* ]]
}

@test "cog plan-review save rejects a relative --repo-root" {
  run --separate-stderr cog plan-review save \
    --plan "$PLAN_INPUT" --request "$REQUEST_INPUT" --repo-root relative/repo

  assert_failure
  [[ $stderr == *"err.kind: InvalidInput"* ]]
}

@test "cog plan-review items supports human and JSON output" {
  write_review_and_plan
  run cog plan-review items "$REVIEW"
  assert_success
  [[ $output == *"PLAN_REVIEW_ITEM_COUNT=3"* ]]
  run cog plan-review items "$REVIEW" --json
  assert_success
  printf '%s\n' "$output" | jq -e '.schema=="cog.plan-review.items.v1" and .count==3' >/dev/null
}

@test "cog plan-review fold-check reports full coverage and waiver" {
  write_review_and_plan
  run cog plan-review fold-check --review "$REVIEW" --plan "$FOLDED" --manifest "$MANIFEST"
  assert_success
  [[ $output == "PLAN_REVIEW_FOLD_VALID total=3 folded=2 waived=1" ]]
  run cog plan-review fold-check --review "$REVIEW" --plan "$FOLDED" --manifest "$MANIFEST" --json
  assert_success
  printf '%s\n' "$output" | jq -e '.schema=="cog.plan-review.fold-check.v1" and .ok' >/dev/null
}

@test "cog plan-review new modes reject relative paths and incomplete manifests" {
  write_review_and_plan
  run --separate-stderr cog plan-review items relative.md --json
  assert_failure
  jq '.dispositions |= .[0:1]' "$MANIFEST" >"${MANIFEST}.bad"
  run cog plan-review fold-check --review "$REVIEW" --plan "$FOLDED" --manifest "${MANIFEST}.bad" --json
  assert_failure 65
  printf '%s\n' "$output" | jq -e '(.ok|not) and (.errors|length)>0' >/dev/null
}

@test "cog plan-review fold-check reports a malformed manifest as data, not a parse crash" {
  write_review_and_plan
  printf '{"schema":"cog.plan-review.fold-manifest.v1","dispositions":[]}\n{"stray":1}\n' >"${MANIFEST}.stream"
  run cog plan-review fold-check --review "$REVIEW" --plan "$FOLDED" --manifest "${MANIFEST}.stream" --json
  assert_failure 65
  printf '%s\n' "$output" | jq -e '
    .schema=="cog.plan-review.fold-check.v1" and (.ok|not) and
    ([.errors[].code] | index("invalid_manifest")) and (.manifest_sha256|length)==64
  ' >/dev/null

  printf 'not json at all\n' >"${MANIFEST}.garbage"
  run cog plan-review fold-check --review "$REVIEW" --plan "$FOLDED" --manifest "${MANIFEST}.garbage" --json
  assert_failure 65
  printf '%s\n' "$output" | jq -e '.schema=="cog.plan-review.fold-check.v1" and (.ok|not)' >/dev/null
}
