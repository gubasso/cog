setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
}

@test "power-grade tier resolves a named tier to its Claude and Codex cells" {
  run cog power-grade tier --name low --json

  assert_success
  printf '%s\n' "$output" | jq -e '
    .schema == "cog.power-grade.tier.v1" and
    .ok == true and
    .tier == "low" and
    .claude.model == "claude-opus-4-8" and
    .claude.effort == "low" and
    .codex.model == "gpt-5.4" and
    .codex.effort == "medium"
  ' >/dev/null
}

@test "power-grade tier resolves the cheap tier to Haiku with no effort" {
  run cog power-grade tier --name cheap --json

  assert_success
  printf '%s\n' "$output" | jq -e '
    .ok == true and
    .claude.model == "claude-haiku-4-5" and
    .claude.effort == "none"
  ' >/dev/null
}

@test "power-grade tier fails for an unknown tier name" {
  run cog power-grade tier --name bogus --json

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

# A '-codex' launcher delegates the substantive turn to Codex, so the suffix is
# matched ahead of the base prefix and rides LOW by rule, not by registry pin.
@test "power-grade skill-tier defaults a codex launcher to low over its base prefix" {
  # review-plan-oneshot-codex is pinned in no registry, so its low tier can only
  # come from the suffix rule beating the review-plan-* high default.
  run cog power-grade skill-tier --skill review-plan-oneshot-codex --json

  assert_success
  printf '%s\n' "$output" | jq -e '
    .ok == true and
    .skill == "review-plan-oneshot-codex" and
    .expected == "low" and
    .actual == "low" and
    .reason == "prefix-default"
  ' >/dev/null

  # plan-oneshot-codex rides the same rule, and its reason is asserted too:
  # cog::fn::data_root prefers the XDG install over the repo copy, so anything
  # weaker here passes against a registry the install has not caught up to.
  run cog power-grade skill-tier --skill plan-oneshot-codex --json

  assert_success
  printf '%s\n' "$output" | jq -e '
    .expected == "low" and
    .actual == "low" and
    .reason == "prefix-default"
  ' >/dev/null

  # executor-oneshot-codex is deliberately absent: it is registry-pinned to the
  # session-default rung, so it demonstrates the registry beating both, not the
  # suffix rule beating the base prefix.
}

# The base prefixes still govern a non-launcher sibling that no registry pins.
@test "power-grade skill-tier keeps base prefix defaults for non-launcher siblings" {
  run cog power-grade skill-tier --skill executor-doc-writeback --json

  assert_success
  printf '%s\n' "$output" | jq -e '
    .expected == "medium" and
    .actual == "medium" and
    .reason == "prefix-default"
  ' >/dev/null

  # review-plan-multi lands on high through the registry rather than the
  # review-plan-* prefix, so it is asserted on the tier alone.
  run cog power-grade skill-tier --skill review-plan-multi --json

  assert_success
  printf '%s\n' "$output" | jq -e '.expected == "high" and .actual == "high"' >/dev/null
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
  run cog power-grade skill-tier --file "${BATS_TEST_DIRNAME}/../../skills/claude/bootstrap-repo/SKILL.md" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.skill == "bootstrap-repo" and .expected == "low" and .actual == "low"' >/dev/null
}

@test "power-grade skill-tier requires a skill identifier" {
  run cog power-grade skill-tier --json

  assert_failure
}
