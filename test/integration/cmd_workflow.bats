setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup

  REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
  ADR="${REPO_ROOT}/docs/decisions/0023-select-workflow-engines-at-definition-or-call-site.md"
  SLICE_002="${REPO_ROOT}/docs/plan/slices/002-workflow-engine-go-no-go/README.md"
  SLICE_003="${REPO_ROOT}/docs/plan/slices/003-linear-workflow-vertical/README.md"
  PLAN_ZONE="${REPO_ROOT}/docs/plan"
}

# Slice 002 is a decision-only slice: its acceptance is that the workflow
# decision is recorded and that no runtime data exists yet. Slice 003 adds the
# `cog workflow` command tests to this file once the command exists.

@test "the workflow decision is recorded in an accepted ADR" {
  assert_file_exists "$ADR"

  run sed -n '/^## Status$/,$p' "$ADR"
  assert_success
  [[ $output == *"Accepted"* ]]

  run grep -c 'engine' "$ADR"
  assert_success
}

@test "the workflow decision is indexed in the decision register" {
  run grep -F '0023-select-workflow-engines-at-definition-or-call-site.md' \
    "${REPO_ROOT}/docs/decisions/README.md"

  assert_success
}

@test "the slice 002 contract enumerates all eleven engines" {
  local engines=(
    claude-haiku-4.5-none
    claude-opus-4.8-low claude-opus-4.8-medium claude-opus-4.8-high
    claude-opus-4.8-xhigh claude-opus-4.8-max
    codex-gpt-5.5-minimal codex-gpt-5.5-low codex-gpt-5.5-medium
    codex-gpt-5.5-high codex-gpt-5.5-xhigh
  )
  local contract
  contract="$(cat "$SLICE_002")"

  # The seed line uses brace notation, so match each engine by its parts.
  [[ $contract == *"eleven engines"* ]]
  local engine provider_model effort
  for engine in "${engines[@]}"; do
    provider_model="${engine%-*}"
    effort="${engine##*-}"
    [[ $contract == *"$provider_model"* ]] || fail "missing engine family: $provider_model"
    [[ $contract == *"$effort"* ]] || fail "missing effort: $effort"
  done
}

@test "the slice 002 contract enumerates the five validator invariants" {
  local invariants=(
    "derived ids" "unique ids" "exactly four fields"
    "provider-valid efforts" "an existing provider runner"
  )
  local contract invariant
  contract="$(cat "$SLICE_002")"

  for invariant in "${invariants[@]}"; do
    [[ $contract == *"$invariant"* ]] || fail "missing invariant: $invariant"
  done
}

@test "the engine contract admits exactly two writers" {
  local contract
  contract="$(cat "$SLICE_002")"

  # shellcheck disable=SC2016 # backticked literal, not an expansion
  [[ $contract == *'`engine:` is required on a step definition and optional on a call site'* ]]
  [[ $contract == *"never reaches into a referenced workflow's interior"* ]]
}

@test "no tier flag survives in the plan zone" {
  run grep -rF --include='*.md' \
    --exclude-dir=001-documentation-architecture-reset -- '--tier' "$PLAN_ZONE"

  # The only permitted survivals are the Done-when and Revisions records
  # naming what ADR-0023 removed.
  local line
  while IFS= read -r line; do
    [[ -z $line || $line == *"ADR-0023"* ]] || fail "live --tier reference: $line"
  done <<<"$output"
}

@test "no engine override map survives in the workflow contract" {
  # The Revisions record names the removed map as history; the contract must not.
  run sed -n '/^## In scope$/,/^## Out of scope$/p' "$SLICE_002"
  assert_success
  [[ $output != *'cells'* ]] || fail "slice 002 In scope still names a cells map"
  # shellcheck disable=SC2016 # backticked literal, not an expansion
  [[ $output != *'`engines:`'* ]] || fail "slice 002 In scope still names an engines map"

  # shellcheck disable=SC2016 # backticked literal, not an expansion
  run grep -E '`cells:`|`engines:`' "$SLICE_003"
  assert_failure
}

@test "the decision creates no runtime workflow data" {
  assert_not_exist "${REPO_ROOT}/data/workflow"
  assert_not_exist "${REPO_ROOT}/lib/commands/cmd_workflow.sh"
}
