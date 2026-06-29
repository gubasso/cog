setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
}

@test "power-grade validate reports matrix warnings without failing" {
  run cog power-grade validate --json

  assert_success
  printf '%s\n' "$output" | jq -e '
	  .schema == "cog.power-grade.validate.v1" and
	  .ok == true and
	  .profile_count == 27 and
	  ([.warnings[] | select(.kind == "needs_verification")] | length) == 1 and
	  ([.warnings[] | select(.kind == "sourced_without_allowlisted_source")] | length) == 0 and
	  ([.warnings[] | select(.kind == "tier3_source_cited")] | length) == 0 and
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
	  (.profile.source_refs | length > 0) and
	  (.profile.benchmark_source_ids | length > 0)
	' >/dev/null
}

@test "power-grade cleared claude opus 4.7 cell has allowlisted benchmark sources" {
  run cog power-grade cell --model claude-opus-4-7 --effort high --json

  assert_success
  printf '%s\n' "$output" | jq -e '
    .schema == "cog.power-grade.cell.v1" and
    .ok == true and
    .profile.id == "claude-opus-4.7-high" and
    .profile.evidence_status == "sourced" and
    (.profile.benchmark_source_ids | index("aws-bedrock-anthropic-opus-4-7") != null) and
    (.profile.benchmark_source_ids | index("vals-ai") != null)
  ' >/dev/null
}

@test "power-grade cleared gpt-5.4-mini cell has allowlisted benchmark sources" {
  run cog power-grade cell --model gpt-5.4-mini --effort medium --json

  assert_success
  printf '%s\n' "$output" | jq -e '
    .schema == "cog.power-grade.cell.v1" and
    .ok == true and
    .profile.id == "codex-gpt-5.4-mini-medium" and
    .profile.evidence_status == "sourced" and
    (.profile.benchmark_source_ids | index("digitalapplied-gpt-5-4-mini-swebench-pro") != null) and
    (.profile.benchmark_source_ids | index("openai-gpt-5-4-mini-announcement") != null)
  ' >/dev/null
}

@test "power-grade classify returns executable profiles at or above grade" {
  run cog power-grade classify --grade 9 --json

  assert_success
  printf '%s\n' "$output" | jq -e '
    .schema == "cog.power-grade.classify.v1" and
    .ok == true and
    all(.profiles[]; .executable == true and .policy_selectable == true and .grade >= 9) and
    ([.profiles[].id] | index("codex-gpt-5.3-codex-spark-needs-verification") == null)
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

@test "power-grade profile resolves a named tier to its Claude and Codex cells" {
  run cog power-grade profile --name low --json

  assert_success
  printf '%s\n' "$output" | jq -e '
    .schema == "cog.power-grade.profile.v1" and
    .ok == true and
    .tier == "low" and
    .claude.model == "claude-opus-4-8" and
    .claude.effort == "low" and
    .codex.model == "gpt-5.4" and
    .codex.effort == "medium"
  ' >/dev/null
}

@test "power-grade profile resolves the cheap tier to Haiku with no effort" {
  run cog power-grade profile --name cheap --json

  assert_success
  printf '%s\n' "$output" | jq -e '
    .ok == true and
    .claude.model == "claude-haiku-4-5" and
    .claude.effort == "none"
  ' >/dev/null
}

@test "power-grade profile fails for an unknown tier name" {
  run cog power-grade profile --name bogus --json

  assert_failure 65
  printf '%s\n' "$output" | jq -e '.ok == false and .claude == null and .codex == null' >/dev/null
}

@test "power-grade skill-tier confirms a registry-pinned exception" {
  run cog power-grade skill-tier --skill executor-prex --json

  assert_success
  printf '%s\n' "$output" | jq -e '
    .schema == "cog.power-grade.skill-tier.v1" and
    .ok == true and
    .skill == "executor-prex" and
    .expected == "high" and
    .actual == "high" and
    .reason == "registry"
  ' >/dev/null
}

@test "power-grade skill-tier reports an ungoverned skill as exempt" {
  run cog power-grade skill-tier --skill context-builder --json

  assert_success
  printf '%s\n' "$output" | jq -e '
    .ok == true and
    .expected == "exempt" and
    .reason == "exempt"
  ' >/dev/null
}

@test "power-grade skill-tier accepts an explicit --file" {
  run cog power-grade skill-tier --file "${BATS_TEST_DIRNAME}/../../skills/claude/runner-all/SKILL.md" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.skill == "runner-all" and .expected == "low" and .actual == "low"' >/dev/null
}

@test "power-grade skill-tier requires a skill identifier" {
  run cog power-grade skill-tier --json

  assert_failure
}
