setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  export XDG_RUNTIME_DIR="${BATS_TEST_TMPDIR}/runtime"
  mkdir -p "$HOME" "$XDG_STATE_HOME" "$XDG_RUNTIME_DIR"
}

@test "cog executor init classifies prompt input and returns the gated 2-stage flow" {
  run cog executor init --executor executor-vetted --engine claude --input "Implement thing" --json

  assert_success
  printf '%s\n' "$output" | jq -e \
    '.schema == "cog.executor.init.v2" and
     .input == {kind: "prompt", value: "Implement thing", plan_path: null} and
     .executor == "executor-vetted" and
     .engine == "claude" and
     .stages == ["prepare","execution"] and
     .flow.family == "vetted" and
     .flow.engine_scope == "claude" and
     .flow.prepare_producers["needs-plan"].skill == "/plan-vetted" and
     .flow.prepare_producers["good-input"].skill == "/plan-vetted" and
     (.phases | length) == 2 and
     .phases[0].artifact == "prepared-plan.md" and
     .phases[1].artifact == "execution-report.md" and
     .artifacts.schema == "cog.executor.artifacts.v2"' >/dev/null
  local run_dir
  run_dir="$(printf '%s\n' "$output" | jq -r '.run_dir')"
  [ -d "$run_dir" ]
  assert_file_exists "${run_dir}/request.md"
  assert_file_contains "${run_dir}/executor" "executor-vetted"
  assert_file_contains "${run_dir}/engine" "claude"
  assert_file_contains "${run_dir}/input-kind" "prompt"
}

@test "cog executor init records plan input but still runs the prepare stage" {
  local plan="${BATS_TEST_TMPDIR}/plan.md"
  printf '%s\n' "# a plan" >"$plan"

  run cog executor init --executor executor-oneshot --engine claude --input "$plan" --json

  assert_success
  printf '%s\n' "$output" | jq -e \
    '.input.kind == "plan" and
     .executor == "executor-oneshot" and
     .stages == ["prepare","execution"]' >/dev/null
  local run_dir
  run_dir="$(printf '%s\n' "$output" | jq -r '.run_dir')"
  assert_file_contains "${run_dir}/plan-source" "$plan"
  [ ! -e "${run_dir}/request.md" ]
}

@test "cog executor init oneshot prompt returns the gated oneshot flow" {
  run cog executor init --executor executor-oneshot --engine codex --input "Implement thing" --json

  assert_success
  printf '%s\n' "$output" | jq -e \
    '.schema == "cog.executor.init.v2" and
     .executor == "executor-oneshot" and
     .engine == "codex" and
     .flow.family == "oneshot" and
     .flow.prepare_producers["needs-plan"].skill == "/plan-oneshot" and
     .flow.prepare_producers["good-input"].skill == "/review-plan-oneshot" and
     .stages == ["prepare","execution"] and
     .phases[1].phase == "execution"' >/dev/null
}

@test "cog executor init rejects a codex engine for the Claude-only vetted executor" {
  run --separate-stderr cog executor init --executor executor-vetted --engine codex --input "x"

  assert_failure
  [[ $stderr == *"Claude-only"* ]]
}

@test "cog executor init rejects removed plan-engine option" {
  run --separate-stderr cog executor init --executor executor-vetted --engine claude --input "x" --plan-engine claude

  assert_failure
  [[ $stderr == *"unknown executor init option"* ]]
  [[ $stderr == *"--plan-engine"* ]]
}

@test "cog executor prepare-step resolves oneshot producers with cross-engine review" {
  run cog executor prepare-step --executor executor-oneshot --engine claude --route needs-plan --json
  assert_success
  printf '%s\n' "$output" | jq -e \
    '.producer == "/plan-oneshot" and .prepare_engine == "claude" and .lane == "agent"' >/dev/null

  run cog executor prepare-step --executor executor-oneshot --engine claude --route good-input --json
  assert_success
  printf '%s\n' "$output" | jq -e \
    '.producer == "/review-plan-oneshot" and .prepare_engine == "codex" and .lane == "codex-runner"' >/dev/null

  run cog executor prepare-step --executor executor-oneshot --engine codex --route good-input --json
  assert_success
  printf '%s\n' "$output" | jq -e \
    '.producer == "/review-plan-oneshot" and .prepare_engine == "claude" and .lane == "agent"' >/dev/null
}

@test "cog executor prepare-step resolves the vetted-plan producer on claude" {
  run cog executor prepare-step --executor executor-vetted --engine claude --route needs-plan --json
  assert_success
  printf '%s\n' "$output" | jq -e \
    '.producer == "/plan-vetted" and .prepare_engine == "claude" and .lane == "agent"' >/dev/null

  run cog executor prepare-step --executor executor-vetted --engine claude --route good-input --json
  assert_success
  printf '%s\n' "$output" | jq -e \
    '.producer == "/plan-vetted" and .prepare_engine == "claude"' >/dev/null
}

@test "cog executor prepare-step resolves plan-vetted's multi producers on claude" {
  run cog executor prepare-step --executor plan-vetted --engine claude --route needs-plan --json
  assert_success
  printf '%s\n' "$output" | jq -e \
    '.producer == "/plan-multi" and .prepare_engine == "claude" and .lane == "agent"' >/dev/null

  run cog executor prepare-step --executor plan-vetted --engine claude --route good-input --json
  assert_success
  printf '%s\n' "$output" | jq -e \
    '.producer == "/review-plan-multi" and .prepare_engine == "claude" and .lane == "agent"' >/dev/null
}

@test "cog executor plan-vetted flow is a single prepare phase and rejects codex" {
  run cog executor init --executor plan-vetted --engine claude --input "Implement thing" --json
  assert_success
  printf '%s\n' "$output" | jq -e \
    '.executor == "plan-vetted" and
     .stages == ["prepare"] and
     (.phases | length) == 1 and
     .phases[0].artifact == "prepared-plan.md"' >/dev/null

  run --separate-stderr cog executor init --executor plan-vetted --engine codex --input "x"
  assert_failure
}

@test "cog executor export-prepared copies prepared-plan.md to a caller output" {
  local run_dir
  run_dir="$(cog executor init --executor plan-vetted --engine claude --input "Implement thing" --json | jq -r '.run_dir')"
  printf '# vetted plan\n' >"${run_dir}/prepared-plan.md"
  local dest="${BATS_TEST_TMPDIR}/out.md"

  run cog executor export-prepared --run-dir "$run_dir" --output "$dest" --json
  assert_success
  printf '%s\n' "$output" | jq -e \
    '.schema == "cog.executor.export-prepared.v1" and .ok == true and (.path | endswith("/out.md"))' >/dev/null
  assert_file_contains "$dest" "vetted plan"
}

@test "cog executor export-prepared rejects a missing prepared plan" {
  local run_dir
  run_dir="$(cog executor init --executor plan-vetted --engine claude --input "Implement thing" --json | jq -r '.run_dir')"
  run --separate-stderr cog executor export-prepared --run-dir "$run_dir" --output "${BATS_TEST_TMPDIR}/out.md"
  assert_failure
}

@test "cog executor prepare-step rejects an invalid route" {
  run --separate-stderr cog executor prepare-step --executor executor-oneshot --engine claude --route maybe --json

  assert_failure
  [[ $stderr == *"invalid executor route"* ]]
}

@test "cog executor classify-input treats missing md path as prompt without stages" {
  run cog executor classify-input "missing.md" --json

  assert_success
  printf '%s\n' "$output" | jq -e \
    '.kind == "prompt" and .value == "missing.md" and .plan_path == null and (has("stages") | not)' >/dev/null
}

@test "cog executor artifacts returns the gated phase-keyed canonical paths" {
  local run_dir
  run_dir="$(cog executor init --executor executor-vetted --engine claude --input "Implement thing" --json | jq -r '.run_dir')"

  run cog executor artifacts "$run_dir" --json

  assert_success
  printf '%s\n' "$output" | jq -e \
    '.schema == "cog.executor.artifacts.v2" and
     .executor == "executor-vetted" and
     (.phases | length) == 2 and
     .phases[0].path == "'"${run_dir}"'/prepared-plan.md" and
     .phases[1].path == "'"${run_dir}"'/execution-report.md" and
     .summary == "'"${run_dir}"'/executor-summary.json"' >/dev/null
}

@test "cog executor artifacts rejects uninitialized directory" {
  local run_dir="${BATS_TEST_TMPDIR}/run"
  mkdir -p "$run_dir"

  run --separate-stderr cog executor artifacts "$run_dir" --json

  assert_failure
  [[ $stderr == *"InvalidInput"* ]]
  [[ $stderr == *"not initialized"* ]]
}

@test "cog executor adopt-prepared copies a producer artifact into prepared-plan.md" {
  local run_dir source
  run_dir="$(cog executor init --executor executor-vetted --engine claude --input "Implement thing" --json | jq -r '.run_dir')"
  source="${BATS_TEST_TMPDIR}/review.md"
  printf '%s\n' "# reviewed plan" >"$source"

  run cog executor adopt-prepared --run-dir "$run_dir" --from "$source" --json

  assert_success
  printf '%s\n' "$output" | jq -e \
    '.schema == "cog.executor.adopt-prepared.v1" and .ok == true and (.path | endswith("/prepared-plan.md"))' >/dev/null
  assert_file_contains "${run_dir}/prepared-plan.md" "reviewed plan"
}

@test "cog executor adopt-prepared rejects an empty source" {
  local run_dir source
  run_dir="$(cog executor init --executor executor-vetted --engine claude --input "Implement thing" --json | jq -r '.run_dir')"
  source="${BATS_TEST_TMPDIR}/empty.md"
  : >"$source"

  run --separate-stderr cog executor adopt-prepared --run-dir "$run_dir" --from "$source"

  assert_failure
  [[ $stderr == *"missing or empty"* ]]
}

@test "cog executor adopt places a staged report at the canonical execution slot" {
  local run_dir source
  run_dir="$(cog executor init --executor executor-oneshot --engine claude --input "do thing" --json | jq -r '.run_dir')"
  # The orchestrator may stage its report under any working name; cog owns the canonical name.
  source="${run_dir}/stage2-execution.md"
  printf '%s\n' "# report body" >"$source"

  run cog executor adopt --run-dir "$run_dir" --ordinal execution --from "$source" --json

  assert_success
  printf '%s\n' "$output" | jq -e \
    '.schema == "cog.executor.adopt-artifact.v1" and .ok == true and .ordinal == "execution" and (.path | endswith("/execution-report.md"))' >/dev/null
  assert_file_contains "${run_dir}/execution-report.md" "report body"
}

@test "cog executor adopt rejects an empty source" {
  local run_dir source
  run_dir="$(cog executor init --executor executor-oneshot --engine claude --input "do thing" --json | jq -r '.run_dir')"
  source="${BATS_TEST_TMPDIR}/empty.md"
  : >"$source"

  run --separate-stderr cog executor adopt --run-dir "$run_dir" --ordinal execution --from "$source"

  assert_failure
  [[ $stderr == *"missing or empty"* ]]
}

@test "cog executor adopt rejects an unknown ordinal" {
  local run_dir source
  run_dir="$(cog executor init --executor executor-oneshot --engine claude --input "do thing" --json | jq -r '.run_dir')"
  source="${BATS_TEST_TMPDIR}/report.md"
  printf '%s\n' "# report" >"$source"

  run --separate-stderr cog executor adopt --run-dir "$run_dir" --ordinal bogus --from "$source"

  assert_failure
  [[ $stderr == *"unknown executor artifact stage"* ]]
}

@test "cog executor verify-artifact passes for a present non-empty artifact" {
  local run_dir source
  run_dir="$(cog executor init --executor executor-oneshot --engine claude --input "do thing" --json | jq -r '.run_dir')"
  source="${run_dir}/report.md"
  printf '%s\n' "# report" >"$source"
  cog executor adopt --run-dir "$run_dir" --ordinal execution --from "$source" --json >/dev/null

  run cog executor verify-artifact --run-dir "$run_dir" --ordinal execution --json

  assert_success
  printf '%s\n' "$output" | jq -e \
    '.schema == "cog.executor.verify-artifact.v1" and .ok == true and .ordinal == "execution" and (.path | endswith("/execution-report.md"))' >/dev/null
}

@test "cog executor verify-artifact fails closed for a missing artifact" {
  local run_dir
  run_dir="$(cog executor init --executor executor-oneshot --engine claude --input "do thing" --json | jq -r '.run_dir')"

  run --separate-stderr cog executor verify-artifact --run-dir "$run_dir" --ordinal execution

  assert_failure
  [[ $stderr == *"missing or empty"* ]]
}

@test "cog executor queue-prompts emits recognition data without the removed vetted twins" {
  run cog executor queue-prompts --json

  assert_success
  printf '%s\n' "$output" | jq -e \
    '.schema == "cog.executor.queue-prompts.v1" and (.prompts | length) == 4' >/dev/null
  printf '%s\n' "$output" | jq -e \
    '[.prompts[].slash] as $s |
     ($s | index("/executor-prex")) and
     ($s | index("/executor-vetted")) and
     ($s | index("/executor-oneshot")) and
     ($s | index("/executor-oneshot-codex")) and
     ($s | index("/executor-vetted-codex") | not)' >/dev/null
  printf '%s\n' "$output" | jq -e \
    '.match.namespace == "executor" and .match.target_argument == "-ar" and (.match.aliases | length) == 0' >/dev/null
}

@test "cog executor summary writes v3 JSON with route and producer for vetted" {
  local run_dir
  run_dir="$(cog executor init --executor executor-vetted --engine claude --input "Implement thing" --json | jq -r '.run_dir')"

  run cog executor summary --run-dir "$run_dir" --executor executor-vetted --engine claude \
    --route needs-plan --prepare "done" --execution "done" --json

  assert_success
  printf '%s\n' "$output" | jq -e \
    '.schema == "cog.executor.summary.v3" and
     .ok == true and
     .executor == "executor-vetted" and
     .engine == "claude" and
     .route == "needs-plan" and
     .producer == "/plan-vetted" and
     .prepare_engine == "claude" and
     .input_kind == "prompt" and
     .stages.prepare.status == "done" and
     .stages.prepare.phase == "prepare" and
     .stages.execution.phase == "execution" and
     .stages.execution.artifact == "execution-report.md"' >/dev/null
  assert_file_exists "${run_dir}/executor-summary.json"
}

@test "cog executor summary records cross-engine review for oneshot good-input" {
  local run_dir
  run_dir="$(cog executor init --executor executor-oneshot --engine claude --input "Implement thing" --json | jq -r '.run_dir')"

  run cog executor summary --run-dir "$run_dir" --executor executor-oneshot --engine claude \
    --route good-input --prepare "done" --execution "done" --json

  assert_success
  printf '%s\n' "$output" | jq -e \
    '.schema == "cog.executor.summary.v3" and
     .route == "good-input" and
     .producer == "/review-plan-oneshot" and
     .prepare_engine == "codex" and
     .execute_engine == "claude"' >/dev/null
}

@test "cog executor summary prints RESOLVED in non-JSON mode" {
  local run_dir
  run_dir="$(cog executor init --executor executor-vetted --engine claude --input "Implement thing" --json | jq -r '.run_dir')"

  run cog executor summary --run-dir "$run_dir" --executor executor-vetted --engine claude \
    --route needs-plan --prepare "done" --execution "done"

  assert_success
  [[ $output == *"RESOLVED ${run_dir}/executor-summary.json"* ]]
}

@test "cog executor summary rejects an invalid route" {
  local run_dir
  run_dir="$(cog executor init --executor executor-vetted --engine claude --input "Implement thing" --json | jq -r '.run_dir')"

  run --separate-stderr cog executor summary --run-dir "$run_dir" --executor executor-vetted --engine claude \
    --route maybe --prepare "done" --execution "done"

  assert_failure
  [[ $stderr == *"invalid executor route"* ]]
}

@test "cog executor summary rejects the removed reviewer option" {
  local run_dir
  run_dir="$(cog executor init --executor executor-vetted --engine claude --input "Implement thing" --json | jq -r '.run_dir')"

  run --separate-stderr cog executor summary --run-dir "$run_dir" --executor executor-vetted --engine claude \
    --route needs-plan --reviewer /review-plan-oneshot --prepare "done" --execution "done"

  assert_failure
  [[ $stderr == *"unknown summary option"* ]]
}

@test "cog executor --help dispatches" {
  run cog executor --help

  assert_success
  [[ $output == *"Usage: cog executor"* ]]
  [[ $output == *"Manage shared executor run contracts and stage artifacts."* ]]
}
