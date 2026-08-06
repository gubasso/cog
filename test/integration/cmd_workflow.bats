setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup

  REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
  DECISIONS="${REPO_ROOT}/docs/decisions"
  ACCEPT_ADR="${DECISIONS}/0027-accept-the-workflow-engine.md"
  CONTRACT="${REPO_ROOT}/docs/reference/workflow-contract.md"
  SLICE_002="${REPO_ROOT}/docs/plan/slices/002-workflow-engine-go-no-go/README.md"
  SLICE_003="${REPO_ROOT}/docs/plan/slices/003-linear-workflow-vertical/README.md"
  PLAN_ZONE="${REPO_ROOT}/docs/plan"
  MILESTONES="${PLAN_ZONE}/milestones.md"
}

# Slice 002 is a decision-only slice: its acceptance is that the workflow
# decision is recorded, that the published contract carries what was accepted,
# and that no runtime data exists yet. Slice 003 adds the `cog workflow`
# command tests to this file once the command exists.

@test "the workflow decision is recorded in an accepted ADR" {
  assert_file_exists "$ACCEPT_ADR"

  run sed -n '/^## Status$/,$p' "$ACCEPT_ADR"
  assert_success
  [[ $output == *"Accepted"* ]]

  run grep -c 'workflow' "$ACCEPT_ADR"
  assert_success
}

@test "every workflow decision is indexed in the decision register" {
  local record
  for record in \
    0023-select-workflow-engines-at-definition-or-call-site.md \
    0024-pass-step-artifacts-by-directory.md \
    0025-needs-is-the-only-edge-directive.md \
    0026-judge-loop-convergence-with-a-prose-criterion.md \
    0027-accept-the-workflow-engine.md; do
    assert_file_exists "${DECISIONS}/${record}"

    run grep -F "$record" "${DECISIONS}/README.md"
    assert_success
  done
}

@test "the published contract enumerates all eleven engines" {
  local engines=(
    claude-haiku-4.5-none
    claude-opus-4.8-low claude-opus-4.8-medium claude-opus-4.8-high
    claude-opus-4.8-xhigh claude-opus-4.8-max
    codex-gpt-5.5-minimal codex-gpt-5.5-low codex-gpt-5.5-medium
    codex-gpt-5.5-high codex-gpt-5.5-xhigh
  )
  local contract
  contract="$(cat "$CONTRACT")"

  # The seed line abbreviates the shared prefix, so match each engine by parts.
  [[ $contract == *"eleven engines"* ]]
  local engine provider_model effort
  for engine in "${engines[@]}"; do
    provider_model="${engine%-*}"
    effort="${engine##*-}"
    [[ $contract == *"$provider_model"* ]] || fail "missing engine family: $provider_model"
    [[ $contract == *"$effort"* ]] || fail "missing effort: $effort"
  done
}

@test "the published contract enumerates the five validator invariants" {
  local invariants=(
    "derived ids" "unique ids" "exactly four fields"
    "provider-valid efforts" "an existing provider runner"
  )
  local contract invariant
  contract="$(cat "$CONTRACT")"

  for invariant in "${invariants[@]}"; do
    [[ $contract == *"$invariant"* ]] || fail "missing invariant: $invariant"
  done
}

@test "the engine contract admits exactly two writers" {
  local contract
  contract="$(cat "$CONTRACT")"

  # shellcheck disable=SC2016 # backticked literal, not an expansion
  [[ $contract == *'`engine:` is required on a step definition and optional on a call site'* ]]
  [[ $contract == *"never reaches into a referenced workflow's interior"* ]]
}

@test "needs is the only edge directive in the published contract" {
  local contract
  contract="$(cat "$CONTRACT")"

  # shellcheck disable=SC2016 # backticked literal, not an expansion
  [[ $contract == *'`needs:` is the only edge key'* ]]
  # shellcheck disable=SC2016 # backticked literal, not an expansion
  [[ $contract == *'no `sync:` marker'* ]] || fail "the contract does not record the removed marker"
}

@test "no sync marker survives as a live workflow key" {
  # The Revisions record and the removed-constructs list name it as history;
  # no key table, validator rule, or driver obligation may still require it.
  # shellcheck disable=SC2016 # grep pattern, not an expansion
  run grep -rniE '^[[:space:]-]*sync:|honor `sync`|definition-owned `sync`' \
    --include='*.md' "$PLAN_ZONE" "$CONTRACT"

  assert_failure
}

@test "no expression dialect survives in the workflow contract" {
  # shellcheck disable=SC2016 # grep pattern, not an expansion
  run grep -rF '${{' --include='*.md' "$PLAN_ZONE" "$CONTRACT"
  assert_failure

  local contract
  contract="$(cat "$CONTRACT")"
  [[ $contract == *"no expression language"* ]]
}

@test "the published contract carries a judged loop criterion" {
  local contract
  contract="$(cat "$CONTRACT")"

  # shellcheck disable=SC2016 # backticked literal, not an expansion
  [[ $contract == *'`until:` is a prose criterion cog stores and never parses'* ]]
  # shellcheck disable=SC2016 # backticked literal, not an expansion
  [[ $contract == *'`max_rounds:` is a hard ceiling'* ]]
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

  # shellcheck disable=SC2016 # backticked literal, not an expansion
  run grep -E '`cells:`|`engines:`' "$CONTRACT"
  assert_failure
}

@test "an accepted engine leaves no slice cut" {
  # Slice 002 acceptance line 2 is the rejection branch: on a rejection the
  # milestone surface marks 003 through 009 `cut`. The engine was accepted, so
  # the counterfactual must hold in the other direction.
  run sed -n '/^## Status$/,$p' "$ACCEPT_ADR"
  assert_success
  [[ $output == *"Accepted"* ]]

  run grep -E '^- [0-9]{3} .* — cut — ' "$MILESTONES"
  assert_failure
}

@test "the decision creates no runtime workflow data" {
  assert_not_exist "${REPO_ROOT}/data/workflow"
  assert_not_exist "${REPO_ROOT}/lib/commands/cmd_workflow.sh"
}
