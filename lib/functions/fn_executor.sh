# shellcheck shell=bash

__cog_executor_summary_self_check='(.schema=="cog.executor.summary.v3") and (.ok|type=="boolean") and (.route|type=="string") and (.stages|type=="object")'

# Executor flows are gated 2-phase pipelines: a route-dependent prepare stage
# (the input-quality verdict picks plan generation vs. plan review) followed by
# execution. The verdict itself is probabilistic and lives in the assess-input
# skill; cog owns the deterministic flow, producer resolution, and summary.
cog::fn::executor::flow_json() {
  case "${1:-}" in
    executor-vetted)
      jq -cn '{
        executor: "executor-vetted",
        family: "vetted",
        engine_scope: "claude",
        phases: [
          {ordinal: "stage1", phase: "prepare", artifact: "prepared-plan.md"},
          {ordinal: "stage2", phase: "execution", artifact: "stage2-execution.md"}
        ],
        prepare_producers: {
          "needs-plan": {skill: "/plan-multi", engine_rule: "claude"},
          "good-input": {skill: "/review-plan-multi", engine_rule: "claude"}
        }
      }'
      ;;
    executor-oneshot)
      jq -cn '{
        executor: "executor-oneshot",
        family: "oneshot",
        engine_scope: "any",
        phases: [
          {ordinal: "stage1", phase: "prepare", artifact: "prepared-plan.md"},
          {ordinal: "stage2", phase: "execution", artifact: "stage2-execution.md"}
        ],
        prepare_producers: {
          "needs-plan": {skill: "/plan-oneshot", engine_rule: "same"},
          "good-input": {skill: "/review-plan-oneshot", engine_rule: "other"}
        }
      }'
      ;;
    *)
      cog::fn::error_raise "InvalidInput" \
        "unknown executor" "executor: ${1:-}" \
        "expected executor-vetted or executor-oneshot" ""
      ;;
  esac
}

cog::fn::executor::validate_engine() {
  case "${1:-}" in
    claude | codex)
      printf '%s\n' "$1"
      ;;
    *)
      cog::fn::error_raise "InvalidInput" \
        "unknown executor engine" "engine: ${1:-}" \
        "expected claude or codex" ""
      ;;
  esac
}

# executor-vetted is a Claude-only orchestrator (its multi producers are
# Claude-only); reject a codex engine for a claude-scoped flow.
cog::fn::executor::validate_engine_for_executor() {
  local executor="${1:-}" engine="${2:-}" scope
  cog::fn::executor::validate_engine "$engine" >/dev/null
  scope="$(cog::fn::executor::flow_json "$executor" | jq -r '.engine_scope')"
  if [[ $scope == claude && $engine != claude ]]; then
    cog::fn::error_raise "InvalidInput" \
      "executor is Claude-only" "executor: ${executor}, engine: ${engine}" \
      "expected engine claude" "pass --engine claude"
  fi
}

cog::fn::executor::validate_route() {
  case "${1:-}" in
    needs-plan | good-input) return 0 ;;
    *) cog::fn::error_raise "InvalidInput" "invalid executor route" "route: ${1:-}" \
      "expected needs-plan or good-input" "" ;;
  esac
}

# Resolve the prepare-stage producer skill, the engine it runs on, and the
# invocation lane for an (executor, engine, route) triple.
cog::fn::executor::prepare_step_json() {
  local executor="${1:-}" engine="${2:-}" route="${3:-}"
  local flow producer skill engine_rule prepare_engine lane artifact

  cog::fn::executor::validate_engine_for_executor "$executor" "$engine"
  cog::fn::executor::validate_route "$route"
  flow="$(cog::fn::executor::flow_json "$executor")"
  producer="$(jq -c --arg r "$route" '.prepare_producers[$r]' <<<"$flow")"
  skill="$(jq -r '.skill' <<<"$producer")"
  engine_rule="$(jq -r '.engine_rule' <<<"$producer")"
  artifact="$(jq -r '.phases[] | select(.phase == "prepare") | .artifact' <<<"$flow")"

  case "$engine_rule" in
    same) prepare_engine="$engine" ;;
    other) [[ $engine == claude ]] && prepare_engine=codex || prepare_engine=claude ;;
    claude) prepare_engine=claude ;;
    *) cog::fn::error_raise "InvalidInput" "invalid producer engine rule" "engine_rule: ${engine_rule}" \
      "expected same, other, or claude" "" ;;
  esac
  [[ $prepare_engine == codex ]] && lane=codex-runner || lane=agent

  jq -cn \
    --arg executor "$executor" \
    --arg engine "$engine" \
    --arg route "$route" \
    --arg producer "$skill" \
    --arg prepare_engine "$prepare_engine" \
    --arg lane "$lane" \
    --arg artifact "$artifact" \
    '{schema: "cog.executor.prepare-step.v1", executor: $executor, engine: $engine, route: $route,
      producer: $producer, prepare_engine: $prepare_engine, lane: $lane, artifact: $artifact}'
}

cog::fn::executor::artifact_name() {
  local executor="${1:-}" ordinal="${2:-}" flow_json artifact

  if [[ $# -eq 1 && $executor == summary ]]; then
    printf '%s\n' executor-summary.json
    return 0
  fi
  if [[ $ordinal == summary ]]; then
    printf '%s\n' executor-summary.json
    return 0
  fi

  [[ -n $executor && -n $ordinal ]] || cog::fn::error_raise "MissingArgument" \
    "missing executor artifact argument" \
    "function: cog::fn::executor::artifact_name" "" \
    "pass executor name and stage ordinal"

  flow_json="$(cog::fn::executor::flow_json "$executor")"
  artifact="$(jq -r --arg ordinal "$ordinal" '.phases[] | select(.ordinal == $ordinal) | .artifact' <<<"$flow_json")"
  [[ -n $artifact ]] || cog::fn::error_raise "InvalidInput" \
    "unknown executor artifact stage" "executor: ${executor}, stage: ${ordinal}" \
    "expected one of the executor flow ordinals or summary" ""
  printf '%s\n' "$artifact"
}

# The prepare stage always runs (it produces or reviews the plan), so the stage
# list is the full phase list regardless of input kind.
cog::fn::executor::stages_json() {
  local executor="${1:-}" flow_json
  flow_json="$(cog::fn::executor::flow_json "$executor")"
  jq -c '[.phases[].ordinal]' <<<"$flow_json"
}

cog::fn::executor::artifacts_json() {
  local run_dir="${1:-}" executor_file executor flow_json phases_json summary

  [[ -n $run_dir ]] || cog::fn::error_raise "MissingArgument" \
    "missing executor run directory" "function: cog::fn::executor::artifacts_json" "" \
    "pass a run directory"
  [[ -d $run_dir ]] || cog::fn::error_raise "InputNotFound" \
    "executor run directory not found" "path: ${run_dir}" "" "check run directory"

  executor_file="$(cog::fn::rundir_path "$run_dir" executor)"
  [[ -s $executor_file ]] || cog::fn::error_raise "InvalidInput" \
    "executor run directory is not initialized" "path: ${run_dir}" \
    "missing state file: ${executor_file}" \
    "initialize the run directory with 'cog executor init'"

  executor="$(<"$executor_file")"
  flow_json="$(cog::fn::executor::flow_json "$executor")"
  phases_json="$(jq -c --arg run_dir "$run_dir" \
    '[.phases[] | {ordinal, phase, artifact, path: ($run_dir + "/" + .artifact)}]' \
    <<<"$flow_json")"
  summary="$(cog::fn::rundir_path "$run_dir" "$(cog::fn::executor::artifact_name "$executor" summary)")"

  jq -cn \
    --arg schema "cog.executor.artifacts.v2" \
    --arg executor "$executor" \
    --argjson phases "$phases_json" \
    --arg summary "$summary" \
    '{schema: $schema, executor: $executor, phases: $phases, summary: $summary}'
}

# Adopt a producer artifact whose output path the executor does not control (the
# review-plan-multi coordinator writes to its own run dir) into the canonical
# prepared-plan.md slot, so the prepare-stage postcondition stays uniform.
cog::fn::executor::adopt_prepared_json() {
  local run_dir="${1:-}" from="${2:-}" dest

  [[ -n $run_dir && -n $from ]] || cog::fn::error_raise "MissingArgument" \
    "missing adopt-prepared argument" "function: cog::fn::executor::adopt_prepared_json" "" \
    "pass a run directory and a source path"
  [[ -d $run_dir ]] || cog::fn::error_raise "InputNotFound" \
    "executor run directory not found" "path: ${run_dir}" "" "check the run directory"
  cog::fn::rundir_require_file "$from" "prepared plan source"

  dest="$(cog::fn::rundir_path "$run_dir" prepared-plan.md)"
  cp -- "$from" "$dest" || cog::fn::error_raise "JsonWriteFailed" \
    "could not adopt prepared plan" "from: ${from}, to: ${dest}" "" "check run directory permissions"

  jq -cn --arg from "$from" --arg path "$dest" \
    '{schema: "cog.executor.adopt-prepared.v1", ok: true, from: $from, path: $path}'
}

cog::fn::executor::classify_input_json() {
  local input="${1:-}" plan_path=""

  [[ -n $input ]] || cog::fn::error_raise "MissingArgument" \
    "missing executor input" "function: cog::fn::executor::classify_input_json" "" \
    "pass a prompt or an existing .md plan path"

  if [[ $input == *.md && -f $input && -r $input ]]; then
    plan_path="$(realpath -- "$input")"
    jq -cn \
      --arg kind plan \
      --arg value "$input" \
      --arg plan_path "$plan_path" \
      '{kind: $kind, value: $value, plan_path: $plan_path}'
    return 0
  fi

  jq -cn \
    --arg kind prompt \
    --arg value "$input" \
    '{kind: $kind, value: $value, plan_path: null}'
}

cog::fn::executor::queue_prompts_json() {
  jq -cn '{
    schema: "cog.executor.queue-prompts.v1",
    match: {
      namespace: "executor",
      target_argument: "-ar",
      name_pattern: "^[a-z0-9-]{1,64}$",
      aliases: {}
    },
    prompts: [
      {
        skill: "executor-prex",
        slash: "/executor-prex",
        aliases: [],
        accepts: ["-ar <target>"],
        target_argument: "-ar",
        stage_model: "executor-prex"
      },
      {
        skill: "executor-vetted",
        slash: "/executor-vetted",
        aliases: [],
        accepts: ["<prompt>", "<plan.md>"],
        target_argument: null,
        stage_model: "executor-gated-2-stage"
      },
      {
        skill: "executor-oneshot",
        slash: "/executor-oneshot",
        aliases: [],
        accepts: ["<prompt>", "<plan.md>"],
        target_argument: null,
        stage_model: "executor-gated-2-stage"
      },
      {
        skill: "executor-oneshot-codex",
        slash: "/executor-oneshot-codex",
        aliases: [],
        accepts: ["<prompt>", "<plan.md>"],
        target_argument: null,
        stage_model: "executor-gated-2-stage"
      }
    ]
  }'
}

cog::fn::executor::resolve_alias() {
  local token="${1:-}" canonical
  canonical="$(cog::fn::executor::queue_prompts_json \
    | jq -r --arg t "/${token}" '.match.aliases[$t] // empty')"
  printf '%s\n' "${canonical:-$token}"
}

cog::fn::executor::summary_self_check() {
  printf '%s\n' "$__cog_executor_summary_self_check"
}

cog::fn::executor::summary_json() {
  local run_dir="${1:-}" executor="${2:-}" engine="${3:-}" route="${4:-}"
  shift 4 || true
  local flow_json prepare_step producer prepare_engine artifacts_json summary_path
  local statuses_json pair ordinal status stages_json input_kind input_kind_file

  [[ -n $run_dir && -n $executor && -n $engine && -n $route ]] \
    || cog::fn::error_raise "MissingArgument" \
      "missing executor summary argument" \
      "function: cog::fn::executor::summary_json" "" \
      "pass run-dir, executor, engine, route, and stage statuses"

  flow_json="$(cog::fn::executor::flow_json "$executor")"
  cog::fn::executor::validate_engine_for_executor "$executor" "$engine"
  cog::fn::executor::validate_route "$route"
  prepare_step="$(cog::fn::executor::prepare_step_json "$executor" "$engine" "$route")"
  producer="$(jq -r '.producer' <<<"$prepare_step")"
  prepare_engine="$(jq -r '.prepare_engine' <<<"$prepare_step")"
  artifacts_json="$(cog::fn::executor::artifacts_json "$run_dir")"
  summary_path="$(jq -r '.summary' <<<"$artifacts_json")"

  input_kind="unknown"
  input_kind_file="$(cog::fn::rundir_path "$run_dir" input-kind)"
  [[ -r $input_kind_file ]] && input_kind="$(<"$input_kind_file")"

  statuses_json='{}'
  for pair in "$@"; do
    ordinal="${pair%%=*}"
    status="${pair#*=}"
    statuses_json="$(jq -c --arg ordinal "$ordinal" --arg status "$status" \
      '. + {($ordinal): $status}' <<<"$statuses_json")"
  done

  stages_json="$(jq -c \
    --argjson statuses "$statuses_json" \
    '[.phases[] | {key: .ordinal, value: {status: ($statuses[.ordinal] // ""), phase: .phase, artifact: .artifact}}] | from_entries' \
    <<<"$flow_json")"

  jq -cn \
    --argjson ok true \
    --arg executor "$executor" \
    --arg engine "$engine" \
    --arg run_dir "$run_dir" \
    --arg route "$route" \
    --arg input_kind "$input_kind" \
    --arg producer "$producer" \
    --arg prepare_engine "$prepare_engine" \
    --arg execute_engine "$engine" \
    --argjson stages "$stages_json" \
    --arg summary "$summary_path" \
    '{
      schema: "cog.executor.summary.v3",
      ok: $ok,
      executor: $executor,
      engine: $engine,
      run_dir: $run_dir,
      route: $route,
      input_kind: $input_kind,
      producer: $producer,
      prepare_engine: $prepare_engine,
      execute_engine: $execute_engine,
      stages: $stages,
      artifacts: {summary: $summary}
    }'
}

cog::fn::executor::write_summary_json() {
  local json summary_path

  json="$(cog::fn::executor::summary_json "$@")"
  summary_path="$(jq -r '.artifacts.summary' <<<"$json")"
  cog::fn::json_write_fragment "$summary_path" "$__cog_executor_summary_self_check" "$json"
}
