setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  mkdir -p "$HOME" "$XDG_STATE_HOME"
}

@test "cog plan-doc --help prints usage" {
  run cog plan-doc --help

  assert_success
  [[ $output == *"Usage: cog plan-doc"* ]]
}

@test "cog plan-doc save writes default runtime artifact" {
  run cog plan-doc save --title "Lean Plan Artifact"

  assert_success
  assert_line --regexp '^PLAN_DOC_PATH=.*lean-plan-artifact\.md$'
  local output_path="${output#PLAN_DOC_PATH=}"
  [[ $output_path == "$XDG_STATE_HOME"/cog/runs/plan-doc-lean-plan-artifact-*"/lean-plan-artifact.md" ]]
  [ -f "$output_path" ]
}

@test "cog plan-doc save writes user output path" {
  local out="${BATS_TEST_TMPDIR}/custom/plan.md"

  run cog plan-doc save --title "Custom Plan" --output "$out"

  assert_success
  assert_output "PLAN_DOC_PATH=${out}"
  [ -f "$out" ]
}

@test "cog plan-doc validate succeeds for generated artifact" {
  local out="${BATS_TEST_TMPDIR}/plan.md"
  run cog plan-doc save --title "Validate Plan" --output "$out"
  assert_success

  run cog plan-doc validate "$out"

  assert_success
  assert_output "PLAN_DOC_VALID"
}

@test "cog --json plan-doc save emits schema action and ok" {
  run cog --json plan-doc save --title "JSON Plan"

  assert_success
  printf '%s\n' "$output" | jq -e '
    .schema == "cog.plan-doc.v1" and .action == "save" and .ok == true
  ' >/dev/null
}

@test "cog plan-doc default path reuses plan-slug normalization" {
  run cog plan-doc save --title "Plan artifacts + Queue!"

  assert_success
  local output_path="${output#PLAN_DOC_PATH=}"
  [[ $output_path == *"plan-artifacts-queue.md" ]]
}

@test "cog plan-doc save rejects a relative --repo-root" {
  run --separate-stderr cog plan-doc save --title "Rel Repo" --repo-root relative/repo

  assert_failure
  [[ $stderr == *"err.kind: InvalidInput"* ]]
}

@test "cog plan-doc validate rejects an annotated plan review" {
  local review="${BATS_TEST_TMPDIR}/review.md"
  printf '# Annotated Plan Review\n\n## Verdict\n\nMODIFIED\n\n## Annotated Plan\n\n### APPROVED\n\n### MODIFIED\n\n### REMOVED\n\n### ADDED\n' >"$review"
  run cog plan-doc validate "$review" --json
  assert_failure 65
  printf '%s\n' "$output" | jq -e '(.ok|not)' >/dev/null
}
