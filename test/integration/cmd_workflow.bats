setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup

  REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
  DECISIONS="${REPO_ROOT}/docs/decisions"
  ACCEPT_ADR="${DECISIONS}/ADR-0027-accept-the-workflow-engine.md"
  CONTRACT="${REPO_ROOT}/docs/reference/workflow-contract.md"
  SLICE_002="${REPO_ROOT}/docs/plan/slices/002-workflow-engine-go-no-go/README.md"
  SLICE_003="${REPO_ROOT}/docs/plan/slices/003-linear-workflow-vertical/README.md"
  PLAN_ZONE="${REPO_ROOT}/docs/plan"
  MILESTONES="${PLAN_ZONE}/milestones.md"

  # cog::fn::data_root prefers the installed XDG root whenever it exists, and
  # _common_setup only defaults XDG_DATA_HOME when it is unset. Override it
  # unconditionally so the run reads the checkout's data/ and workflow/ as the
  # installed layer rather than whatever the developer has installed.
  export XDG_DATA_HOME="${BATS_TEST_TMPDIR}/data"

  RUN_DIR="${BATS_TEST_TMPDIR}/run"
  mkdir -p "$RUN_DIR"
  printf 'stub task\n' >"${RUN_DIR}/task.md"
}

# This file carries two slices. Slice 002 was decision-only: its acceptance is
# that the workflow decision is recorded and that the published contract
# carries what was accepted. Slice 003 adds the `cog workflow` runtime
# coverage below, and owns both of its own acceptance criteria here.

# Walk one node of a resolved run from pending to done, writing one artifact.
_walk_node() {
  local as="$1" token
  token="$(cog workflow claim --run-dir "$RUN_DIR" --as "$as" --owner w1 --json | jq -r '.claim_token')"
  printf 'artifact for %s\n' "$as" >"${RUN_DIR}/${as}/${as}.md"
  cog workflow record --run-dir "$RUN_DIR" --as "$as" --claim-token "$token" --status "done" --json >/dev/null
}

# A project-layer workspace that shadows the installed one, seeded from it.
_project_fixture() {
  local root="${BATS_TEST_TMPDIR}/project-workflow"
  mkdir -p "${root}/workflows" "${root}/steps" "${root}/skills"
  cp "${REPO_ROOT}/workflow/meta.yaml" "${root}/meta.yaml"
  cp "${REPO_ROOT}"/workflow/steps/*.yaml "${root}/steps/"
  cp "${REPO_ROOT}"/workflow/skills/*.md "${root}/skills/"
  printf '%s\n' "$root"
}

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
    ADR-0023-select-workflow-engines-at-definition-or-call-site.md \
    ADR-0024-pass-step-artifacts-by-directory.md \
    ADR-0025-needs-is-the-only-edge-directive.md \
    ADR-0026-judge-loop-convergence-with-a-prose-criterion.md \
    ADR-0027-accept-the-workflow-engine.md; do
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

@test "the workflow command module exists and declares its desc sentinel" {
  assert_file_exists "${REPO_ROOT}/lib/commands/cmd_workflow.sh"

  run sed -n '2p' "${REPO_ROOT}/lib/commands/cmd_workflow.sh"
  assert_success
  [[ $output == ": 'desc: "* ]] || fail "line 2 is not a desc sentinel: $output"

  run cog --help
  assert_success
  [[ $output == *"workflow"* ]] || fail "root help does not list the workflow command"
}

# --- acceptance criterion 1 -------------------------------------------------
# When a linear stub is installed, the workflow system shall list, validate,
# resolve, claim, record, and summarize it.

@test "the installed linear stub is listed" {
  run cog workflow list --json
  assert_success
  run jq -e '[.workflows[] | select(.key == "linear-stub")] | length == 1' <<<"$output"
  assert_success
}

@test "show prints the resolved source per file" {
  run cog workflow show linear-stub --json
  assert_success

  # One workflow file plus its three step files, each carrying its own source.
  run jq -e '(.files | length) == 4
    and ([.files[] | select(.role == "workflow")] | length) == 1
    and ([.files[] | select(.role == "step")] | length) == 3
    and ([.files[] | select(.source == null or .source == "")] | length) == 0' <<<"$output"
  assert_success
}

@test "layer resolution is per file, so a project workflow reuses installed steps" {
  local root
  root="$(_project_fixture)"
  rm -f "${root}"/steps/*.yaml
  cat >"${root}/workflows/project-only.yaml" <<'YAML'
id: "project-only"
steps:
  - step: {id: "plan", as: "draft"}
YAML

  COG_WORKFLOW_PROJECT_ROOT="$root" run cog workflow show project-only --json
  assert_success

  # The workflow resolves from the project layer; the step it references has no
  # project-layer file and resolves from the installed layer instead.
  run jq -e '
    ([.files[] | select(.role == "workflow")] | first | .source) == "project"
    and ([.files[] | select(.role == "step" and .id == "plan")] | first | .source) == "installed"' <<<"$output"
  assert_success
}

@test "the installed linear stub validates clean" {
  run cog workflow validate linear-stub --json
  assert_success
  run jq -e '.findings == [] and .ok == true' <<<"$output"
  assert_success
}

@test "resolve creates one directory per node and a state file" {
  run cog workflow resolve --key linear-stub --run-dir "$RUN_DIR" \
    --task-file "${RUN_DIR}/task.md" --json
  assert_success

  assert_file_exists "${RUN_DIR}/state.json"
  assert_dir_exists "${RUN_DIR}/draft"
  assert_dir_exists "${RUN_DIR}/vet"
  assert_dir_exists "${RUN_DIR}/apply"

  run jq -e '.nodes | length == 3' <<<"$output"
  assert_success
}

@test "the linear stub runs list, validate, resolve, claim, record, and summarize end to end" {
  run cog workflow resolve --key linear-stub --run-dir "$RUN_DIR" \
    --task-file "${RUN_DIR}/task.md" --json
  assert_success

  # next hands out one node at a time, in needs: order.
  run cog workflow next --run-dir "$RUN_DIR" --json
  assert_success
  run jq -er '.node.as' <<<"$output"
  assert_output "draft"

  _walk_node draft

  run cog workflow next --run-dir "$RUN_DIR" --json
  assert_success
  run jq -er '.node.as' <<<"$output"
  assert_output "vet"

  # needs: hands every upstream directory to the step that depends on it.
  run cog workflow next --run-dir "$RUN_DIR" --json
  run jq -e '.node.inputs == ["draft/"]' <<<"$output"
  assert_success

  _walk_node vet

  run cog workflow next --run-dir "$RUN_DIR" --json
  assert_success
  run jq -e '.node.as == "apply" and (.node.inputs == ["draft/", "vet/"])' <<<"$output"
  assert_success

  _walk_node apply

  # Every node terminal: the run state is completed and reported at exit 0.
  run cog workflow next --run-dir "$RUN_DIR" --json
  assert_success
  run jq -e '.state == "completed" and .node == null' <<<"$output"
  assert_success

  run cog workflow summary --run-dir "$RUN_DIR" --json
  assert_success
  run jq -e '.state == "completed"
    and (.nodes | length) == 3
    and ([.nodes[] | select(.status == "done")] | length) == 3' <<<"$output"
  assert_success

  run cog workflow conformance --run-dir "$RUN_DIR"
  assert_success
}

@test "each record writes a receipt whose key set is exactly closed" {
  run cog workflow resolve --key linear-stub --run-dir "$RUN_DIR" \
    --task-file "${RUN_DIR}/task.md" --json
  assert_success
  _walk_node draft

  assert_file_exists "${RUN_DIR}/draft/outputs.json"
  run jq -e '(keys_unsorted | sort) == ["as","engine","error","final_message",
    "final_message_truncated","inputs","outputs","owner","schema","status"]' \
    "${RUN_DIR}/draft/outputs.json"
  assert_success

  # The receipt lists what the directory holds; cog counts files, never reads them.
  run jq -e '(.outputs | length) == 1
    and .outputs[0].path == "draft.md"
    and (.outputs[0].bytes | type) == "number"
    and .outputs[0].bytes > 0
    and .status == "done"' "${RUN_DIR}/draft/outputs.json"
  assert_success
}

@test "a failed node still gets a receipt carrying an error object" {
  run cog workflow resolve --key linear-stub --run-dir "$RUN_DIR" \
    --task-file "${RUN_DIR}/task.md" --json
  assert_success

  local token
  token="$(cog workflow claim --run-dir "$RUN_DIR" --as draft --owner w1 --json | jq -r '.claim_token')"
  run cog workflow record --run-dir "$RUN_DIR" --as draft --claim-token "$token" \
    --status failed --reason "the model refused" --json
  assert_success

  run jq -e '.status == "failed" and .error.reason == "the model refused"' \
    "${RUN_DIR}/draft/outputs.json"
  assert_success
}

# --- acceptance criterion 2 -------------------------------------------------
# If a literal engine on a definition or a call-site override is unknown, then
# validation shall fail before dispatch.

@test "an unknown literal engine on a step definition fails validation before dispatch" {
  local root
  root="$(_project_fixture)"
  cat >"${root}/steps/unknown-engine.yaml" <<'YAML'
id: "unknown-engine"
engine: "codex-gpt-9.9-nope"
skill: "workflow-stub-plan"
YAML
  cat >"${root}/workflows/bad-definition.yaml" <<'YAML'
id: "bad-definition"
steps:
  - step: {id: "unknown-engine", as: "one"}
YAML

  COG_WORKFLOW_PROJECT_ROOT="$root" run cog workflow validate bad-definition --json
  assert_failure 2
  run jq -e '[.findings[] | select(.rule == "engine-literal")] | length > 0' <<<"$output"
  assert_success

  local run_dir="${BATS_TEST_TMPDIR}/bad-def-run"
  mkdir -p "$run_dir"
  printf 'task\n' >"${run_dir}/task.md"
  COG_WORKFLOW_PROJECT_ROOT="$root" run cog workflow resolve --key bad-definition \
    --run-dir "$run_dir" --task-file "${run_dir}/task.md" --json
  assert_failure 2

  # Validation runs before any agent is spawned, so no node directory exists.
  run find "$run_dir" -mindepth 1 -maxdepth 1 -type d
  assert_output ""
}

@test "an unknown literal engine on a call-site override fails validation before dispatch" {
  local root
  root="$(_project_fixture)"
  cat >"${root}/workflows/bad-call-site.yaml" <<'YAML'
id: "bad-call-site"
steps:
  - step: {id: "plan", as: "one", engine: "codex-gpt-9.9-nope"}
YAML

  COG_WORKFLOW_PROJECT_ROOT="$root" run cog workflow validate bad-call-site --json
  assert_failure 2
  run jq -e '[.findings[] | select(.rule == "engine-literal")] | length > 0' <<<"$output"
  assert_success

  local run_dir="${BATS_TEST_TMPDIR}/bad-call-run"
  mkdir -p "$run_dir"
  printf 'task\n' >"${run_dir}/task.md"
  COG_WORKFLOW_PROJECT_ROOT="$root" run cog workflow resolve --key bad-call-site \
    --run-dir "$run_dir" --task-file "${run_dir}/task.md" --json
  assert_failure 2

  run find "$run_dir" -mindepth 1 -maxdepth 1 -type d
  assert_output ""
}

@test "every shipped engine row satisfies the five registry invariants" {
  run cog workflow validate --json
  assert_success
  run jq -e '[.findings[] | select(.rule == "derived-ids" or .rule == "unique-ids"
    or .rule == "exactly-four-fields" or .rule == "provider-valid-efforts"
    or .rule == "existing-provider-runner" or .rule == "registry-shape")] | length == 0' <<<"$output"
  assert_success
}

# --- exit-code protocol -----------------------------------------------------
# 0 valid result or applied transition; 1 internal state failure; 2
# InvalidInput; 75 cannot advance yet. Each assertion pins the exact code: a
# bare assert_failure would pass on 65, which is what the shared error helper
# maps InvalidInput to.

@test "an unknown verb exits 2" {
  run cog workflow bogus
  assert_failure 2
}

@test "an unknown option on a known verb exits 2" {
  run cog workflow list --nope
  assert_failure 2
}

@test "resolve refuses a composite or loop node in the linear vertical" {
  local root
  root="$(_project_fixture)"
  cat >"${root}/workflows/has-loop.yaml" <<'YAML'
id: "has-loop"
steps:
  - loop:
      as: "spin"
      until: "the reviewer reports no further findings"
      max_rounds: 3
      steps:
        - step: {id: "plan", as: "a"}
YAML

  local run_dir="${BATS_TEST_TMPDIR}/loop-run"
  mkdir -p "$run_dir"
  printf 'task\n' >"${run_dir}/task.md"
  COG_WORKFLOW_PROJECT_ROOT="$root" run cog workflow resolve --key has-loop \
    --run-dir "$run_dir" --task-file "${run_dir}/task.md" --json
  assert_failure 2
  run jq -e '[.findings[] | select(.rule == "unsupported-node-kind")] | length > 0' <<<"$output"
  assert_success
}

@test "record with a stale claim token exits 2" {
  run cog workflow resolve --key linear-stub --run-dir "$RUN_DIR" \
    --task-file "${RUN_DIR}/task.md" --json
  assert_success
  cog workflow claim --run-dir "$RUN_DIR" --as draft --owner w1 --json >/dev/null

  run cog workflow record --run-dir "$RUN_DIR" --as draft \
    --claim-token deadbeef --status "done" --json
  assert_failure 2
}

@test "claiming an already-claimed node exits 2" {
  run cog workflow resolve --key linear-stub --run-dir "$RUN_DIR" \
    --task-file "${RUN_DIR}/task.md" --json
  assert_success
  cog workflow claim --run-dir "$RUN_DIR" --as draft --owner w1 --json >/dev/null

  run cog workflow claim --run-dir "$RUN_DIR" --as draft --owner w2 --json
  assert_failure 2
}

@test "claiming a node whose needs are unmet exits 2" {
  run cog workflow resolve --key linear-stub --run-dir "$RUN_DIR" \
    --task-file "${RUN_DIR}/task.md" --json
  assert_success

  run cog workflow claim --run-dir "$RUN_DIR" --as apply --owner w1 --json
  assert_failure 2
}

@test "reclaim takes over a claimed node and rejects a stale previous claim" {
  run cog workflow resolve --key linear-stub --run-dir "$RUN_DIR" \
    --task-file "${RUN_DIR}/task.md" --json
  assert_success

  local token
  token="$(cog workflow claim --run-dir "$RUN_DIR" --as draft --owner w1 --json | jq -r '.claim_token')"

  run cog workflow reclaim --run-dir "$RUN_DIR" --as draft \
    --previous-claim wrong --owner w2 --reason "worker vanished" --json
  assert_failure 2

  run cog workflow reclaim --run-dir "$RUN_DIR" --as draft \
    --previous-claim "$token" --owner w2 --reason "worker vanished" --json
  assert_success
  run jq -e '.claim_token != null and .owner == "w2"' <<<"$output"
  assert_success
}

@test "next on a run with a claimed but unrecorded node exits 75" {
  run cog workflow resolve --key linear-stub --run-dir "$RUN_DIR" \
    --task-file "${RUN_DIR}/task.md" --json
  assert_success
  cog workflow claim --run-dir "$RUN_DIR" --as draft --owner w1 --json >/dev/null

  run cog workflow next --run-dir "$RUN_DIR" --json
  assert_failure 75
}

@test "advance with an unknown loop handle exits 2" {
  run cog workflow resolve --key linear-stub --run-dir "$RUN_DIR" \
    --task-file "${RUN_DIR}/task.md" --json
  assert_success

  run cog workflow advance --run-dir "$RUN_DIR" --loop nope \
    --decision-token x --outcome continue --reason criterion-met --json
  assert_failure 2
}

@test "resolve rejects a missing or empty task file" {
  : >"${RUN_DIR}/empty.md"
  run cog workflow resolve --key linear-stub --run-dir "$RUN_DIR" \
    --task-file "${RUN_DIR}/empty.md" --json
  assert_failure 2

  run cog workflow resolve --key linear-stub --run-dir "$RUN_DIR" \
    --task-file "${RUN_DIR}/absent.md" --json
  assert_failure 2
}

@test "resolve rejects a malformed orchestrator payload" {
  run cog workflow resolve --key linear-stub --run-dir "$RUN_DIR" \
    --task-file "${RUN_DIR}/task.md" --orchestrator 'not-json' --json
  assert_failure 2
}

@test "resolve records the orchestrator budget verbatim without validating it" {
  run cog workflow resolve --key linear-stub --run-dir "$RUN_DIR" \
    --task-file "${RUN_DIR}/task.md" --max-fresh-depth 4 \
    --orchestrator '{"id":"executor-oneshot"}' --json
  assert_success

  # The subagent budget is deliberately not a validator check: cog records what
  # the orchestrator passed from its own remaining budget.
  run jq -e '.max_fresh_depth == 4 and .orchestrator.id == "executor-oneshot"' \
    "${RUN_DIR}/state.json"
  assert_success
}

@test "init copies a shipped definition into the project layer and refuses to clobber it" {
  local root="${BATS_TEST_TMPDIR}/init-root"

  COG_WORKFLOW_PROJECT_ROOT="$root" run cog workflow init mine --from linear-stub --json
  assert_success
  assert_file_exists "${root}/workflows/mine.yaml"
  assert_file_exists "${root}/steps/plan.yaml"

  run yq e -r '.id' "${root}/workflows/mine.yaml"
  assert_output "mine"

  COG_WORKFLOW_PROJECT_ROOT="$root" run cog workflow init mine --from linear-stub --json
  assert_failure 2

  COG_WORKFLOW_PROJECT_ROOT="$root" run cog workflow init mine --from linear-stub --force --json
  assert_success
}

@test "summary reports without gating and conformance fails a tampered run" {
  run cog workflow resolve --key linear-stub --run-dir "$RUN_DIR" \
    --task-file "${RUN_DIR}/task.md" --json
  assert_success
  _walk_node draft

  # summary reports an in-progress run at exit 0.
  run cog workflow summary --run-dir "$RUN_DIR" --json
  assert_success
  run jq -er '.state' <<<"$output"
  assert_output "running"

  # conformance gates: a terminal node whose receipt is gone must fail.
  rm -f "${RUN_DIR}/draft/outputs.json"
  run cog workflow conformance --run-dir "$RUN_DIR"
  assert_failure 2
  [[ $output == *"FAIL receipt draft"* ]] || fail "conformance did not report the missing receipt"
}

@test "a run whose frontier a failed node blocks reaches a terminal state" {
  # Nothing moves a node out of failed, so every node downstream of one is
  # blocked forever. Reporting the run as running would leave next handing out
  # 75 with no transition that could ever clear it.
  run cog workflow resolve --key linear-stub --run-dir "$RUN_DIR" \
    --task-file "${RUN_DIR}/task.md" --json
  assert_success

  local token
  token="$(cog workflow claim --run-dir "$RUN_DIR" --as draft --owner w1 --json | jq -r '.claim_token')"
  run cog workflow record --run-dir "$RUN_DIR" --as draft --claim-token "$token" \
    --status failed --reason "the model refused" --json
  assert_success
  run jq -e '.run_state == "failed"' <<<"$output"
  assert_success

  run cog workflow next --run-dir "$RUN_DIR" --json
  assert_success
  run jq -e '.state == "failed" and .node == null' <<<"$output"
  assert_success

  run cog workflow summary --run-dir "$RUN_DIR" --json
  assert_success
  run jq -e '.state == "failed"' <<<"$output"
  assert_success
}

@test "resolve refuses an instance name that would escape the run directory" {
  local root
  root="$(_project_fixture)"
  cat >"${root}/workflows/escaping.yaml" <<'YAML'
id: "escaping"
steps:
  - step: {id: "plan", as: "../../elsewhere"}
YAML
  COG_WORKFLOW_PROJECT_ROOT="$root" run cog workflow resolve --key escaping \
    --run-dir "$RUN_DIR" --task-file "${RUN_DIR}/task.md" --json
  assert_failure 2
  assert_not_exist "${BATS_TEST_TMPDIR}/elsewhere"
}
