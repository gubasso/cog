setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  command -v taplo >/dev/null 2>&1 || skip "taplo not installed"
}

@test "power-grade validate reports matrix warnings without failing" {
  run cog power-grade validate --json

  assert_success
  printf '%s\n' "$output" | jq -e '
    .schema == "cog.power-grade.validate.v1" and
    .ok == true and
    .profile_count == 32 and
    (.warnings | map(.kind) | index("needs_verification") != null) and
    .errors == []
  ' >/dev/null
}

@test "power-grade cell returns a model effort profile" {
  run cog power-grade cell --model gpt-5.5 --effort medium --json

  assert_success
  printf '%s\n' "$output" | jq -e '
    .schema == "cog.power-grade.cell.v1" and
    .ok == true and
    .profile.id == "codex-gpt-5.5-medium" and
    .profile.grade == 8 and
    (.profile.source_refs | length > 0)
  ' >/dev/null
}

@test "power-grade classify returns executable profiles at or above grade" {
  run cog power-grade classify --grade 9 --json

  assert_success
  printf '%s\n' "$output" | jq -e '
    .schema == "cog.power-grade.classify.v1" and
    .ok == true and
    all(.profiles[]; .executable == true and .policy_selectable == true and .grade >= 9) and
    ([.profiles[].id] | index("codex-gpt-5.3-codex-spark-needs-verification") == null) and
    ([.profiles[].id] | index("claude-fable-5-high") == null)
  ' >/dev/null
}

@test "power-grade compound reads matrix formula and returns stable grade" {
  run cog power-grade compound --passes gpt55-medium,opus48-high --json

  assert_success
  printf '%s\n' "$output" | jq -e '
    .schema == "cog.power-grade.compound.v1" and
    .ok == true and
    .formula.formula == "capped_max_plus_artifact_gain" and
    .base_grade == 8 and
    .artifact_gain == 1 and
    .compound_grade == 9
  ' >/dev/null
}

@test "power-grade cell fails for unknown model effort" {
  run cog power-grade cell --model unknown --effort medium --json

  assert_failure 65
  printf '%s\n' "$output" | jq -e '
    .schema == "cog.power-grade.cell.v1" and
    .ok == false and
    .profile == null
  ' >/dev/null
}

@test "power-grade compound fails for informational profile" {
  run cog power-grade compound --passes gpt53codexspark-needs-verification --json

  assert_failure 65
  printf '%s\n' "$output" | jq -e '
    .schema == "cog.power-grade.compound.v1" and
    .ok == false and
    .errors[0].error == "profile_not_executable"
  ' >/dev/null
}
