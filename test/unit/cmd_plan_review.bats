setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export LIB_DIR="${BATS_TEST_DIRNAME}/../../lib"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  mkdir -p "$HOME" "$XDG_STATE_HOME"
  source "${LIB_DIR}/helpers.sh"
  source "${LIB_DIR}/functions/fn_ui_print.sh"
  source "${LIB_DIR}/functions/fn_log.sh"
  source "${LIB_DIR}/functions/fn_error_raise.sh"
  source "${LIB_DIR}/functions/fn_json_write.sh"
  source "${LIB_DIR}/functions/fn_rundir.sh"
  source "${LIB_DIR}/functions/fn_data.sh"
  source "${LIB_DIR}/functions/fn_research.sh"
  source "${LIB_DIR}/functions/fn_plan_slug.sh"
  source "${LIB_DIR}/functions/fn_plan_artifact.sh"
  source "${LIB_DIR}/functions/fn_plan_review.sh"
  source "${LIB_DIR}/commands/cmd_plan_review.sh"
}

write_inputs() {
  PLAN_INPUT="${BATS_TEST_TMPDIR}/input-plan.md"
  REQUEST_INPUT="${BATS_TEST_TMPDIR}/request.md"
  printf '%s\n' "# Plan" >"$PLAN_INPUT"
  printf '%s\n' "# Request" >"$REQUEST_INPUT"
}

write_annotated_review() {
  local out="$1"
  printf '# Annotated Plan Review\n\n## Verdict\n\nMODIFIED\n\n## Annotated Plan\n\n### APPROVED\n\n- Keep this\n  with detail\n- Keep next\n\n### MODIFIED\n\n1. Change this\n   continued\n\n### REMOVED\n\n#### Old step\n\nRemove it.\n\n### ADDED\n\nAdd tests.\n\nAdd docs.\n\n## Risks\n\n### APPROVED\n\n- ignored\n' >"$out"
}

@test "plan-review template includes review vocabulary" {
  local research_json='{"root":"/tmp/research","index":"/tmp/research/index.jsonl","exists":false}'

  run cog::fn::plan_review::template /tmp/plan.md /tmp/request.md /tmp/repo "$research_json"

  assert_success
  assert_output --partial "APPROVED"
  assert_output --partial "MODIFIED"
  assert_output --partial "REMOVED"
  assert_output --partial "ADDED"
}

@test "plan-review save_json rejects relative input paths" {
  run --separate-stderr cog::fn::plan_review::save_json relative.md /tmp/request.md "" /tmp/repo ""

  assert_failure 65
  [[ $stderr == *"err.kind: InvalidInput"* ]]
}

@test "plan-review save_json writes default runtime artifact" {
  write_inputs

  run cog::fn::plan_review::save_json "$PLAN_INPUT" "$REQUEST_INPUT" "" /tmp/repo ""

  assert_success
  local output_path
  output_path="$(printf '%s\n' "$output" | jq -r '.output_path')"
  [[ $output_path == "$XDG_STATE_HOME"/cog/runs/plan-review-input-plan-md-*"/input-plan-md.md" ]]
  [ -f "$output_path" ]
}

@test "plan-review save_json honors absolute output override" {
  write_inputs
  local out="${BATS_TEST_TMPDIR}/review/out.md"

  run cog::fn::plan_review::save_json "$PLAN_INPUT" "$REQUEST_INPUT" "$out" /tmp/repo ""

  assert_success
  printf '%s\n' "$output" | jq -e --arg out "$out" '.output_path == $out' >/dev/null
  [ -f "$out" ]
}

@test "plan-review orchestrator_json writes three-path artifact" {
  write_inputs
  local out="${BATS_TEST_TMPDIR}/review/orchestrator.md"

  run cog::fn::plan_review::orchestrator_json "$PLAN_INPUT" "$REQUEST_INPUT" "$out"

  assert_success
  printf '%s\n' "$output" | jq -e --arg out "$out" '.action == "orchestrator" and .output_path == $out' >/dev/null
  [ -f "$out" ]
}

@test "plan-review validate_json passes generated artifact" {
  write_inputs
  local out="${BATS_TEST_TMPDIR}/review.md"
  run cog::fn::plan_review::save_json "$PLAN_INPUT" "$REQUEST_INPUT" "$out" /tmp/repo ""
  assert_success

  run cog::fn::plan_review::validate_json "$out"

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and (.errors | length) == 0' >/dev/null
}

@test "plan-review validate_json reports missing vocabulary" {
  local out="${BATS_TEST_TMPDIR}/bad.md"
  printf '%s\n' "# Annotated Plan Review" "## Verdict" >"$out"

  run cog::fn::plan_review::validate_json "$out"

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == false and (.errors | length) > 0' >/dev/null
}

@test "plan-review items extracts stable annotation ordinals and fallbacks" {
  local review="${BATS_TEST_TMPDIR}/annotated.md"
  write_annotated_review "$review"
  run cog::fn::plan_review::items_json "$review"
  assert_success
  printf '%s\n' "$output" | jq -e '
    .schema == "cog.plan-review.items.v1" and .count == 6 and
    [.items[].id] == ["A1","A2","M1","R1","D1","D2"] and
    .items[0].markdown == "Keep this\n  with detail" and
    .items[2].markdown == "Change this\n   continued" and
    .items[3].markdown == "Old step\n\nRemove it." and
    (.items | all(.start_line <= .end_line))
  ' >/dev/null
}

@test "plan-review items supports empty annotation sections" {
  local review="${BATS_TEST_TMPDIR}/empty.md"
  printf '# Annotated Plan Review\n\n## Annotated Plan\n\n### APPROVED\n\n### MODIFIED\n\n### REMOVED\n\n### ADDED\n' >"$review"
  run cog::fn::plan_review::items_json "$review"
  assert_success
  printf '%s\n' "$output" | jq -e '.count == 0 and .items == []' >/dev/null
}

@test "plan-review items stops extracting at an H1 after the annotated plan" {
  local review="${BATS_TEST_TMPDIR}/h1-boundary.md"
  printf '# Annotated Plan Review\n\n## Annotated Plan\n\n### APPROVED\n\n- Inside the region.\n\n# Appendix\n\n### ADDED\n\n- Outside the region.\n' >"$review"
  run cog::fn::plan_review::items_json "$review"
  assert_success
  printf '%s\n' "$output" | jq -e '.count == 1 and .items[0].id == "A1"' >/dev/null
}

@test "plan-review fold-check validates exact coverage and hashes" {
  local review="${BATS_TEST_TMPDIR}/annotated.md" plan="${BATS_TEST_TMPDIR}/plan.md" manifest="${BATS_TEST_TMPDIR}/manifest.json"
  write_annotated_review "$review"
  printf '# Plan\n\n## Goal\n\nG\n\n## Implementation Plan\n\n1. Do\n\n## Acceptance Criteria\n\n- [ ] Done\n' >"$plan"
  jq -n '{schema:"cog.plan-review.fold-manifest.v1", dispositions:["A1","A2","M1","R1","D1"]|map({id:.,disposition:"folded"}) + [{id:"D2",disposition:"waived",reason:"Not in scope"}]}' >"$manifest"
  run cog::fn::plan_review::fold_check_json "$review" "$plan" "$manifest"
  assert_success
  printf '%s\n' "$output" | jq -e '.ok and .counts == {total:6,folded:5,waived:1} and (.review_sha256|length)==64 and (.plan_sha256|length)==64 and (.manifest_sha256|length)==64' >/dev/null
}

@test "plan-review fold-check reports a multi-document manifest structurally" {
  local review="${BATS_TEST_TMPDIR}/review.md" plan="${BATS_TEST_TMPDIR}/plan.md" manifest="${BATS_TEST_TMPDIR}/manifest.json"
  printf '# Annotated Plan Review\n\n## Annotated Plan\n\n### APPROVED\n\n- Keep\n' >"$review"
  printf '# Plan\n' >"$plan"
  printf '{"schema":"cog.plan-review.fold-manifest.v1","dispositions":[]}\n{"stray":1}\n' >"$manifest"
  run cog::fn::plan_review::fold_check_json "$review" "$plan" "$manifest"
  assert_success
  printf '%s\n' "$output" | jq -e '
    .schema == "cog.plan-review.fold-check.v1" and (.ok|not) and
    ([.errors[].code] | index("invalid_manifest")) and (.manifest_sha256|length)==64
  ' >/dev/null
}

@test "plan-review fold receipt hashes become stale after manifest edits" {
  local review="${BATS_TEST_TMPDIR}/review.md" plan="${BATS_TEST_TMPDIR}/plan.md" manifest="${BATS_TEST_TMPDIR}/manifest.json" before after
  printf '# Annotated Plan Review\n\n## Annotated Plan\n\n### APPROVED\n\n- Keep\n\n### MODIFIED\n\n### REMOVED\n\n### ADDED\n' >"$review"
  printf '# Plan\n' >"$plan"
  jq -n '{schema:"cog.plan-review.fold-manifest.v1",dispositions:[{id:"A1",disposition:"folded"}]}' >"$manifest"
  before="$(cog::fn::plan_review::fold_check_json "$review" "$plan" "$manifest" | jq -r '.manifest_sha256')"
  jq -n '{schema:"cog.plan-review.fold-manifest.v1",dispositions:[{id:"A1",disposition:"waived",reason:"Reconsidered"}]}' >"$manifest"
  after="$(cog::fn::plan_review::fold_check_json "$review" "$plan" "$manifest" | jq -r '.manifest_sha256')"
  [ "$before" != "$after" ]
}

@test "plan-review fold-check fails closed for duplicate missing unknown and bad waivers" {
  local review="${BATS_TEST_TMPDIR}/annotated.md" plan="${BATS_TEST_TMPDIR}/plan.md" manifest="${BATS_TEST_TMPDIR}/manifest.json"
  write_annotated_review "$review"
  printf '# Plan\n' >"$plan"
  jq -n '{schema:"cog.plan-review.fold-manifest.v1", dispositions:[{id:"A1",disposition:"folded"},{id:"A1",disposition:"folded"},{id:"Z1",disposition:"folded"},{id:"A2",disposition:"waived",reason:" "}]}' >"$manifest"
  run cog::fn::plan_review::fold_check_json "$review" "$plan" "$manifest"
  assert_success
  printf '%s\n' "$output" | jq -e '(.ok|not) and ([.errors[].code] | index("duplicate_id")) and ([.errors[].code] | index("unknown_id")) and ([.errors[].code] | index("missing_id")) and ([.errors[].code] | index("blank_waiver_reason"))' >/dev/null
}

@test "plan-review fold receipt hashes become stale after plan edits" {
  local review="${BATS_TEST_TMPDIR}/review.md" plan="${BATS_TEST_TMPDIR}/plan.md" manifest="${BATS_TEST_TMPDIR}/manifest.json" before after
  printf '# Annotated Plan Review\n\n## Annotated Plan\n\n### APPROVED\n\n- Keep\n\n### MODIFIED\n\n### REMOVED\n\n### ADDED\n' >"$review"
  printf '# Plan\n' >"$plan"
  jq -n '{schema:"cog.plan-review.fold-manifest.v1",dispositions:[{id:"A1",disposition:"folded"}]}' >"$manifest"
  before="$(cog::fn::plan_review::fold_check_json "$review" "$plan" "$manifest" | jq -r '.plan_sha256')"
  printf '\nchanged\n' >>"$plan"
  after="$(cog::fn::plan_review::fold_check_json "$review" "$plan" "$manifest" | jq -r '.plan_sha256')"
  [ "$before" != "$after" ]
}

@test "plan-review fold-check accepts an empty manifest only for zero items" {
  local review="${BATS_TEST_TMPDIR}/review.md" plan="${BATS_TEST_TMPDIR}/plan.md" manifest="${BATS_TEST_TMPDIR}/manifest.json"
  printf '# Annotated Plan Review\n\n## Annotated Plan\n\n### APPROVED\n\n### MODIFIED\n\n### REMOVED\n\n### ADDED\n' >"$review"
  printf '# Plan\n' >"$plan"
  jq -n '{schema:"cog.plan-review.fold-manifest.v1",dispositions:[]}' >"$manifest"
  run cog::fn::plan_review::fold_check_json "$review" "$plan" "$manifest"
  assert_success
  printf '%s\n' "$output" | jq -e '.ok and .counts.total==0' >/dev/null
}

@test "plan-review fold-check reports malformed manifest objects without jq crashes" {
  local review="${BATS_TEST_TMPDIR}/review.md" plan="${BATS_TEST_TMPDIR}/plan.md" manifest="${BATS_TEST_TMPDIR}/manifest.json"
  printf '# Annotated Plan Review\n\n## Annotated Plan\n\n### APPROVED\n\n- Keep\n\n### MODIFIED\n\n### REMOVED\n\n### ADDED\n' >"$review"
  printf '# Plan\n' >"$plan"
  printf '["not-an-object"]\n' >"$manifest"
  run cog::fn::plan_review::fold_check_json "$review" "$plan" "$manifest"
  assert_success
  printf '%s\n' "$output" | jq -e '(.ok|not) and .errors[0].code=="invalid_manifest"' >/dev/null

  printf '{"schema":"cog.plan-review.fold-manifest.v1","dispositions":["bad"]}\n' >"$manifest"
  run cog::fn::plan_review::fold_check_json "$review" "$plan" "$manifest"
  assert_success
  printf '%s\n' "$output" | jq -e '(.ok|not) and ([.errors[].code]|index("invalid_disposition"))' >/dev/null
}
