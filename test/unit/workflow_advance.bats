#!/usr/bin/env bats

# The advance transition rules, exercised against synthetic run state.
#
# A run resolved by this release carries no loop nodes — resolve refuses
# workflow: and loop: entries — so these fixtures hand-build the state a future
# materializer will produce. The rules are the contract slice 004 inherits, and
# they are enforced now so that slice inherits them working.

setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup

  # See workflow_validate.bats: _common_setup only defaults XDG_DATA_HOME when
  # it is unset, and the installed data root would otherwise win.
  export XDG_DATA_HOME="${BATS_TEST_TMPDIR}/data"

  RUN_DIR="${BATS_TEST_TMPDIR}/run"
  mkdir -p "${RUN_DIR}/spin"
}

# _state <round> <max_rounds> <produced_files>
_state() {
  jq -nc --argjson round "$1" --argjson max "$2" --argjson produced "$3" \
    --arg run "$RUN_DIR" '
    {schema: "cog.workflow.state.v1", key: "synthetic", run_dir: $run,
      task_file: ($run + "/task.md"), state: "running",
      max_fresh_depth: null, orchestrator: null,
      meta: {context: "fresh", max_rounds: 5, max_workflow_depth: 3},
      nodes: [{as: "spin", id: "spin", kind: "loop", needs: [], engine: null,
              skill: null, dir: "spin", status: "claimed",
              claim_token: null, owner: null, reclaims: [],
              decision_token: "tok", round: $round, max_rounds: $max,
              round_produced_files: $produced}]}' >"${RUN_DIR}/state.json"
}

_advance() {
  run cog workflow advance --run-dir "$RUN_DIR" --loop spin \
    --decision-token "$1" --outcome "$2" --reason "$3" --json
}

@test "an unknown loop handle fails closed" {
  _state 0 3 1
  run cog workflow advance --run-dir "$RUN_DIR" --loop ghost \
    --decision-token tok --outcome pause --reason needs-user --json
  assert_failure 2
}

@test "a stale decision token fails closed" {
  _state 0 3 1
  _advance "wrong-token" pause needs-user
  assert_failure 2
}

@test "an outcome outside the closed set fails closed" {
  _state 0 3 1
  _advance tok retry stalled
  assert_failure 2
}

@test "a reason outside the closed set fails closed" {
  _state 0 3 1
  _advance tok pause whatever
  assert_failure 2
}

@test "pause is always an applicable transition" {
  _state 0 3 1
  _advance tok pause needs-user
  assert_success
  run jq -er '.state' <<<"$output"
  assert_output "paused"
}

@test "abort is always an applicable transition" {
  _state 0 3 1
  _advance tok abort unfeasible
  assert_success
  run jq -er '.state' <<<"$output"
  assert_output "failed"
}

@test "a round that produced no files refuses to continue" {
  _state 0 3 0
  _advance tok continue criterion-met
  assert_failure 2
}

@test "a round that produced no files refuses to converge" {
  _state 0 3 0
  _advance tok converged criterion-met
  assert_failure 2
}

@test "advancing past max_rounds is an illegal transition" {
  # Round 3 of 3: one more would exceed the ceiling, and reaching the ceiling
  # is a failure rather than a success.
  _state 3 3 1
  _advance tok continue stalled
  assert_failure 2
}

@test "converging on a non-empty round is applicable even at the ceiling" {
  _state 3 3 1
  _advance tok converged criterion-met
  assert_success
}

@test "a live continue under the ceiling cannot advance yet" {
  # cog materializes round N+1 only on this call, one round at a time. This
  # release has no materializer, so 75 is the honest signal.
  _state 1 3 2
  _advance tok continue criterion-met
  assert_failure 75
}

@test "an applied transition is persisted and spends its decision token" {
  # Exit 0 reports an applied transition, so the run directory must carry it
  # and the same token must not be accepted twice.
  _state 0 3 1
  _advance tok abort unfeasible
  assert_success

  run jq -e '.state == "failed"
    and (.nodes[0].status == "failed")
    and (.nodes[0].decision_token == null)
    and (.nodes[0].last_outcome == "abort")' "${RUN_DIR}/state.json"
  assert_success

  _advance tok abort unfeasible
  assert_failure 2
}

@test "a pause is persisted as the paused run state" {
  _state 0 3 1
  _advance tok pause needs-user
  assert_success

  run jq -e '.state == "paused" and (.nodes[0].decision_token == null)' "${RUN_DIR}/state.json"
  assert_success
}

@test "a continue that cannot advance yet leaves the decision token live" {
  # 75 is "cannot advance yet", not an applied transition: nothing is spent.
  _state 1 3 2
  _advance tok continue criterion-met
  assert_failure 75

  run jq -e '.state == "running" and (.nodes[0].decision_token == "tok")' "${RUN_DIR}/state.json"
  assert_success
}
