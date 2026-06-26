setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
}

@test "cog context-brief gate render emits the canonical stanza" {
  run cog context-brief gate render --skill demo

  assert_success
  # shellcheck disable=SC2016
  expected='<!-- cog-context-brief-gate -->

**Context-brief gate.** Before `/demo` dispatches to any fresh-context worker — an Agent subagent
or a `cog codex-runner` Codex job — build its input as a validated context brief from your whole
accumulated raw context: attach the raw request as-is, author an oriented objective, carry the full
substance and load-bearing artifacts, and omit your own verdict. Build the brief with `cog
context-brief build` and confirm it with `cog context-brief validate` before dispatch.'
  assert_output "$expected"
}

@test "cog context-brief gate render substitutes the skill name" {
  run cog context-brief gate render --skill review-plan-multi

  assert_success
  # shellcheck disable=SC2016
  assert_output --partial 'Before `/review-plan-multi` dispatches'
}

@test "cog context-brief gate render fails without --skill" {
  run --separate-stderr cog context-brief gate render

  assert_failure
  [[ $stderr == *"skill name"* ]]
}

@test "cog context-brief gate render rejects an invalid skill name" {
  run --separate-stderr cog context-brief gate render --skill "Bad Name"

  assert_failure
  [[ $stderr == *"invalid skill name"* ]]
}

@test "cog context-brief gate render rejects an unknown option" {
  run --separate-stderr cog context-brief gate render --skill demo --bogus

  assert_failure
  [[ $stderr == *"unknown context-brief gate render option"* ]]
}

@test "cog context-brief gate without a mode shows usage" {
  run cog context-brief gate

  assert_success
  assert_output --partial 'Usage: cog context-brief gate render --skill <name>'
}

@test "cog context-brief gate rejects an unknown sub-verb" {
  run --separate-stderr cog context-brief gate frobnicate

  assert_failure
  [[ $stderr == *"unknown context-brief gate mode"* ]]
}
