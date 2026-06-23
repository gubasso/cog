# shellcheck shell=bash

__cog_executor_summary_self_check='(.schema=="cog.executor.summary.v2") and (.ok|type=="boolean") and (.stages|type=="object")'

cog::fn::executor::flow_json() {
  case "${1:-}" in
    executor-lean)
      jq -cn '{
        executor: "executor-lean",
        reviewed: true,
        phases: [
          {ordinal: "stage1", phase: "plan", artifact: "stage1-plan.md", skippable: true},
          {ordinal: "stage2", phase: "review", artifact: "stage2-reviewed-plan.md", skippable: false},
          {ordinal: "stage3", phase: "execution", artifact: "stage3-execution.md", skippable: false}
        ]
      }'
      ;;
    executor-single)
      jq -cn '{
        executor: "executor-single",
        reviewed: false,
        phases: [
          {ordinal: "stage1", phase: "plan", artifact: "stage1-plan.md", skippable: true},
          {ordinal: "stage2", phase: "execution", artifact: "stage2-execution.md", skippable: false}
        ]
      }'
      ;;
    *)
      cog::fn::error_raise "InvalidInput" \
        "unknown executor" "executor: ${1:-}" \
        "expected executor-lean or executor-single" ""
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

cog::fn::executor::select_reviewer_json() {
  local executor="${1:-}" engine="${2:-}" flow_json reviewed review_engine reviewer

  flow_json="$(cog::fn::executor::flow_json "$executor")"
  cog::fn::executor::validate_engine "$engine" >/dev/null
  reviewed="$(jq -r '.reviewed' <<<"$flow_json")"

  if [[ $reviewed == true ]]; then
    case "$engine" in
      claude) review_engine=codex ;;
      codex) review_engine=claude ;;
    esac
    reviewer=/review-plan-lean
  else
    review_engine=none
    reviewer=none
  fi

  jq -cn \
    --arg plan_engine "$engine" \
    --arg review_engine "$review_engine" \
    --arg reviewer "$reviewer" \
    '{plan_engine: $plan_engine, review_engine: $review_engine, reviewer: $reviewer}'
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

cog::fn::executor::stages_json() {
  local executor="${1:-}" input_kind="${2:-}" flow_json

  flow_json="$(cog::fn::executor::flow_json "$executor")"
  case "$input_kind" in
    prompt)
      jq -c '[.phases[].ordinal]' <<<"$flow_json"
      ;;
    plan)
      jq -c '[.phases[] | select(.skippable != true) | .ordinal]' <<<"$flow_json"
      ;;
    *)
      cog::fn::error_raise "InvalidInput" \
        "invalid executor input kind" "input-kind: ${input_kind}" \
        "expected prompt or plan" ""
      ;;
  esac
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
        skill: "executor-lean",
        slash: "/executor-lean",
        aliases: [],
        accepts: ["<prompt>", "<plan.md>"],
        target_argument: null,
        stage_model: "executor-3-stage"
      },
      {
        skill: "executor-lean-codex",
        slash: "/executor-lean-codex",
        aliases: [],
        accepts: ["<prompt>", "<plan.md>"],
        target_argument: null,
        stage_model: "executor-3-stage"
      },
      {
        skill: "executor-single",
        slash: "/executor-single",
        aliases: [],
        accepts: ["<prompt>", "<plan.md>"],
        target_argument: null,
        stage_model: "executor-2-stage"
      },
      {
        skill: "executor-single-codex",
        slash: "/executor-single-codex",
        aliases: [],
        accepts: ["<prompt>", "<plan.md>"],
        target_argument: null,
        stage_model: "executor-2-stage"
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
  local run_dir="${1:-}" executor="${2:-}" engine="${3:-}" input_kind="${4:-}" reviewer="${5:-}"
  shift 5 || true
  local flow_json reviewer_json review_engine artifacts_json summary_path statuses_json pair ordinal status stages_json

  [[ -n $run_dir && -n $executor && -n $engine && -n $input_kind && -n $reviewer ]] \
    || cog::fn::error_raise "MissingArgument" \
      "missing executor summary argument" \
      "function: cog::fn::executor::summary_json" "" \
      "pass run-dir, executor, engine, input-kind, reviewer, and stage statuses"

  flow_json="$(cog::fn::executor::flow_json "$executor")"
  cog::fn::executor::validate_engine "$engine" >/dev/null
  reviewer_json="$(cog::fn::executor::select_reviewer_json "$executor" "$engine")"
  review_engine="$(jq -r '.review_engine' <<<"$reviewer_json")"
  artifacts_json="$(cog::fn::executor::artifacts_json "$run_dir")"
  summary_path="$(jq -r '.summary' <<<"$artifacts_json")"

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
    --arg input_kind "$input_kind" \
    --arg plan_engine "$engine" \
    --arg review_engine "$review_engine" \
    --arg reviewer "$reviewer" \
    --argjson stages "$stages_json" \
    --arg summary "$summary_path" \
    '{
      schema: "cog.executor.summary.v2",
      ok: $ok,
      executor: $executor,
      engine: $engine,
      run_dir: $run_dir,
      input_kind: $input_kind,
      plan_engine: $plan_engine,
      review_engine: $review_engine,
      reviewer: $reviewer,
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
