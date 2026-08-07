#!/usr/bin/env bats

setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup

  REPO_ROOT="${BATS_TEST_DIRNAME}/../.."

  # cog::fn::data_root prefers the installed XDG root whenever it exists, and
  # _common_setup only defaults XDG_DATA_HOME when it is unset. Override it
  # unconditionally so these tests read the checkout's data/ and workflow/
  # rather than whatever the developer happens to have installed.
  export XDG_DATA_HOME="${BATS_TEST_TMPDIR}/data"

  FIXTURE="${BATS_TEST_TMPDIR}/workflow"
  mkdir -p "${FIXTURE}/workflows" "${FIXTURE}/steps" "${FIXTURE}/skills"
  cp "${REPO_ROOT}/workflow/meta.yaml" "${FIXTURE}/meta.yaml"
  cp "${REPO_ROOT}"/workflow/steps/*.yaml "${FIXTURE}/steps/"
  cp "${REPO_ROOT}"/workflow/skills/*.md "${FIXTURE}/skills/"
  export COG_WORKFLOW_PROJECT_ROOT="$FIXTURE"
}

# Write a workflow fixture and return the findings JSON for it.
_findings() {
  local key="$1"
  run --separate-stderr cog workflow validate "$key" --json
  printf '%s' "$output"
}

# Assert that validating <key> reports <rule> at least once.
assert_rule() {
  local key="$1" rule="$2" findings
  findings="$(_findings "$key")"
  run jq -e --arg r "$rule" '[.findings[] | select(.rule == $r)] | length > 0' <<<"$findings"
  assert_success || {
    printf 'findings: %s\n' "$findings" >&2
    return 1
  }
}

@test "the shipped linear stub validates clean" {
  unset COG_WORKFLOW_PROJECT_ROOT
  run cog workflow validate linear-stub --json
  assert_success
  run jq -e '.findings == [] and .ok == true' <<<"$output"
  assert_success
}

@test "the shipped engine registry satisfies all five invariants" {
  unset COG_WORKFLOW_PROJECT_ROOT
  run cog workflow validate --json
  assert_success
  # A registry violation would surface under one of the five invariant rules.
  run jq -e '
    [.findings[] | select(.rule == "derived-ids" or .rule == "unique-ids"
      or .rule == "exactly-four-fields" or .rule == "provider-valid-efforts"
      or .rule == "existing-provider-runner" or .rule == "registry-shape")] | length == 0' <<<"$output"
  assert_success
}

@test "rule one-kind-key rejects an entry carrying two kind keys" {
  cat >"${FIXTURE}/workflows/two-kinds.yaml" <<'YAML'
id: "two-kinds"
steps:
  - step: {id: "plan", as: "a"}
    workflow: {id: "other", as: "b"}
YAML
  assert_rule two-kinds one-kind-key
}

@test "rule one-kind-key rejects an entry carrying no kind key" {
  cat >"${FIXTURE}/workflows/no-kind.yaml" <<'YAML'
id: "no-kind"
steps:
  - id: "plan"
YAML
  assert_rule no-kind one-kind-key
}

@test "rule as-unique-and-needs-present rejects a duplicate as" {
  cat >"${FIXTURE}/workflows/dupe-as.yaml" <<'YAML'
id: "dupe-as"
steps:
  - step: {id: "plan", as: "same"}
  - step: {id: "review", as: "same"}
YAML
  assert_rule dupe-as as-unique-and-needs-present
}

@test "rule as-unique-and-needs-present rejects a needs target that is absent" {
  cat >"${FIXTURE}/workflows/dangling.yaml" <<'YAML'
id: "dangling"
steps:
  - step: {id: "plan", as: "a"}
  - step: {id: "review", as: "b", needs: ["ghost"]}
YAML
  assert_rule dangling as-unique-and-needs-present
}

@test "rule no-cycle rejects a two-node needs cycle" {
  cat >"${FIXTURE}/workflows/cycle.yaml" <<'YAML'
id: "cycle"
steps:
  - step: {id: "plan", as: "a", needs: ["b"]}
  - step: {id: "review", as: "b", needs: ["a"]}
YAML
  assert_rule cycle no-cycle
}

@test "rule engine-literal rejects an unknown engine on a step definition" {
  cat >"${FIXTURE}/steps/unknown-engine.yaml" <<'YAML'
id: "unknown-engine"
engine: "codex-gpt-9.9-nope"
skill: "workflow-stub-plan"
YAML
  cat >"${FIXTURE}/workflows/bad-definition.yaml" <<'YAML'
id: "bad-definition"
steps:
  - step: {id: "unknown-engine", as: "a"}
YAML
  assert_rule bad-definition engine-literal
}

@test "rule engine-literal rejects an unknown engine on a call-site override" {
  cat >"${FIXTURE}/workflows/bad-call-site.yaml" <<'YAML'
id: "bad-call-site"
steps:
  - step: {id: "plan", as: "a", engine: "codex-gpt-9.9-nope"}
YAML
  assert_rule bad-call-site engine-literal
}

@test "rule engine-literal rejects an engine that is not a plain literal" {
  cat >"${FIXTURE}/workflows/expression-engine.yaml" <<'YAML'
id: "expression-engine"
steps:
  - step: {id: "plan", as: "a", engine: "codex-${MODEL}-high"}
YAML
  assert_rule expression-engine engine-literal
}

@test "rule engine-literal rejects a step definition carrying no engine" {
  cat >"${FIXTURE}/steps/engineless.yaml" <<'YAML'
id: "engineless"
skill: "workflow-stub-plan"
YAML
  cat >"${FIXTURE}/workflows/engineless-call.yaml" <<'YAML'
id: "engineless-call"
steps:
  - step: {id: "engineless", as: "a"}
YAML
  assert_rule engineless-call engine-literal
}

@test "rule engine-literal rejects an engine on a node that runs no agent" {
  cat >"${FIXTURE}/workflows/engine-on-loop.yaml" <<'YAML'
id: "engine-on-loop"
steps:
  - loop:
      as: "spin"
      until: "the reviewer reports no further findings"
      max_rounds: 3
      engine: "codex-gpt-5.6-sol-high"
      steps:
        - step: {id: "plan", as: "a"}
YAML
  assert_rule engine-on-loop engine-literal
}

@test "rule loop-keys rejects a loop missing max_rounds" {
  cat >"${FIXTURE}/workflows/loop-no-rounds.yaml" <<'YAML'
id: "loop-no-rounds"
steps:
  - loop:
      as: "spin"
      until: "the reviewer reports no further findings"
      steps:
        - step: {id: "plan", as: "a"}
YAML
  assert_rule loop-no-rounds loop-keys
}

@test "rule loop-keys rejects a loop missing until" {
  cat >"${FIXTURE}/workflows/loop-no-until.yaml" <<'YAML'
id: "loop-no-until"
steps:
  - loop:
      as: "spin"
      max_rounds: 3
      steps:
        - step: {id: "plan", as: "a"}
YAML
  assert_rule loop-no-until loop-keys
}

@test "rule scalar-strings rejects an id that parses as a float" {
  cat >"${FIXTURE}/workflows/float-id.yaml" <<'YAML'
id: "float-id"
steps:
  - step: {id: 4.5, as: "a"}
YAML
  assert_rule float-id scalar-strings
}

@test "rule scalar-strings rejects an as that parses as a boolean" {
  # yq reads YAML 1.2, where `no`/`yes`/`on`/`off` stay strings and only
  # true/false are booleans. `true` is the footgun this parser actually has.
  cat >"${FIXTURE}/workflows/bool-as.yaml" <<'YAML'
id: "bool-as"
steps:
  - step: {id: "plan", as: true}
YAML
  assert_rule bool-as scalar-strings
}

@test "rule scalar-strings rejects an empty until" {
  cat >"${FIXTURE}/workflows/empty-until.yaml" <<'YAML'
id: "empty-until"
steps:
  - loop:
      as: "spin"
      until: "   "
      max_rounds: 3
      steps:
        - step: {id: "plan", as: "a"}
YAML
  assert_rule empty-until scalar-strings
}

@test "rule max-rounds-positive rejects zero" {
  cat >"${FIXTURE}/workflows/zero-rounds.yaml" <<'YAML'
id: "zero-rounds"
steps:
  - loop:
      as: "spin"
      until: "the reviewer reports no further findings"
      max_rounds: 0
      steps:
        - step: {id: "plan", as: "a"}
YAML
  assert_rule zero-rounds max-rounds-positive
}

@test "rule max-rounds-positive rejects a non-integer" {
  cat >"${FIXTURE}/workflows/fractional-rounds.yaml" <<'YAML'
id: "fractional-rounds"
steps:
  - loop:
      as: "spin"
      until: "the reviewer reports no further findings"
      max_rounds: 2.5
      steps:
        - step: {id: "plan", as: "a"}
YAML
  assert_rule fractional-rounds max-rounds-positive
}

@test "rule reference-depth rejects nesting past max_workflow_depth" {
  printf 'context: fresh\nmax_rounds: 5\nmax_workflow_depth: 1\n' >"${FIXTURE}/meta.yaml"
  cat >"${FIXTURE}/workflows/deep-root.yaml" <<'YAML'
id: "deep-root"
steps:
  - workflow: {id: "deep-mid", as: "mid"}
YAML
  cat >"${FIXTURE}/workflows/deep-mid.yaml" <<'YAML'
id: "deep-mid"
steps:
  - workflow: {id: "deep-leaf", as: "leaf"}
YAML
  cat >"${FIXTURE}/workflows/deep-leaf.yaml" <<'YAML'
id: "deep-leaf"
steps:
  - step: {id: "plan", as: "a"}
YAML
  assert_rule deep-root reference-depth
}

@test "rule no-cycle rejects a reference cycle across files" {
  cat >"${FIXTURE}/workflows/ping.yaml" <<'YAML'
id: "ping"
steps:
  - workflow: {id: "pong", as: "p"}
YAML
  cat >"${FIXTURE}/workflows/pong.yaml" <<'YAML'
id: "pong"
steps:
  - workflow: {id: "ping", as: "q"}
YAML
  assert_rule ping no-cycle
}

@test "rule no-skill-under-workflows rejects a nested skill key" {
  cat >"${FIXTURE}/workflows/skill-leak.yaml" <<'YAML'
id: "skill-leak"
steps:
  - step: {id: "plan", as: "a", skill: "workflow-stub-plan"}
YAML
  assert_rule skill-leak no-skill-under-workflows
}

@test "an unresolvable step reference is reported rather than ignored" {
  cat >"${FIXTURE}/workflows/ghost-step.yaml" <<'YAML'
id: "ghost-step"
steps:
  - step: {id: "not-a-step", as: "a"}
YAML
  assert_rule ghost-step unresolvable-reference
}

@test "validate exits 2 when any finding is present and 0 when none are" {
  cat >"${FIXTURE}/workflows/clean.yaml" <<'YAML'
id: "clean"
steps:
  - step: {id: "plan", as: "a"}
  - step: {id: "review", as: "b", needs: ["a"]}
YAML
  run cog workflow validate clean --json
  assert_success

  cat >"${FIXTURE}/workflows/dirty.yaml" <<'YAML'
id: "dirty"
steps:
  - step: {id: "plan", as: "a", needs: ["ghost"]}
YAML
  run cog workflow validate dirty --json
  assert_failure 2
}

@test "rule no-cycle rejects a reference cycle whose files were first reached through another branch" {
  # The cycle is between mid and side, and the root reaches both directly. A
  # per-walk ancestor check clears each of them on the root's own branch and
  # never revisits the pair.
  cat >"${FIXTURE}/workflows/fan.yaml" <<'YAML'
id: "fan"
steps:
  - workflow: {id: "mid", as: "m"}
  - workflow: {id: "side", as: "s"}
YAML
  cat >"${FIXTURE}/workflows/mid.yaml" <<'YAML'
id: "mid"
steps:
  - workflow: {id: "side", as: "s"}
YAML
  cat >"${FIXTURE}/workflows/side.yaml" <<'YAML'
id: "side"
steps:
  - workflow: {id: "mid", as: "m"}
YAML
  assert_rule fan no-cycle
}

@test "rule safe-instance-name rejects an as: that escapes the run directory" {
  # as: names the node directory under the run directory, so a traversing value
  # would put node directories and receipts outside the run entirely.
  cat >"${FIXTURE}/workflows/escape.yaml" <<'YAML'
id: "escape"
steps:
  - step: {id: "plan", as: "../../elsewhere"}
YAML
  assert_rule escape safe-instance-name

  cat >"${FIXTURE}/workflows/nested-as.yaml" <<'YAML'
id: "nested-as"
steps:
  - step: {id: "plan", as: "a/b"}
YAML
  assert_rule nested-as safe-instance-name
}

@test "a loop template is validated rather than carried unchecked" {
  # A loop resolves to one node carrying an unexpanded but fully validated
  # template, so an unknown engine inside it is a finding.
  cat >"${FIXTURE}/workflows/loop-template.yaml" <<'YAML'
id: "loop-template"
steps:
  - loop:
      as: "spin"
      until: "the reviewer approves"
      max_rounds: 3
      steps:
        - step: {id: "plan", as: "inner", engine: "codex-gpt-9.9-nope"}
YAML
  assert_rule loop-template engine-literal
}

@test "a malformed container fails closed with a finding rather than a jq abort" {
  cat >"${FIXTURE}/workflows/not-a-list.yaml" <<'YAML'
id: "not-a-list"
steps: nope
YAML
  run cog workflow validate not-a-list --json
  assert_failure 2
  run jq -e '[.findings[] | select(.rule == "workflow-shape")] | length > 0' <<<"$output"
  assert_success
}
