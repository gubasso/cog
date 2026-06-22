# shellcheck shell=bash

__cog_executor_summary_self_check='(.schema=="cog.executor.summary.v1") and (.ok|type=="boolean") and (.stages|type=="object")'

cog::fn::executor::artifact_name() {
  case "${1:-}" in
    stage1)
      printf '%s\n' stage1-plan.md
      ;;
    stage2)
      printf '%s\n' stage2-reviewed-plan.md
      ;;
    stage3)
      printf '%s\n' stage3-execution.md
      ;;
    summary)
      printf '%s\n' executor-summary.json
      ;;
    *)
      cog::fn::error_raise "InvalidInput" \
        "unknown executor artifact stage" "stage: ${1:-}" \
        "expected stage1, stage2, stage3, or summary" ""
      ;;
  esac
}

cog::fn::executor::artifacts_json() {
  local run_dir="${1:-}"
  local stage1 stage2 stage3 summary

  [[ -n $run_dir ]] || cog::fn::error_raise "MissingArgument" \
    "missing executor run directory" "function: cog::fn::executor::artifacts_json" "" \
    "pass a run directory"

  stage1="$(cog::fn::rundir_path "$run_dir" "$(cog::fn::executor::artifact_name stage1)")"
  stage2="$(cog::fn::rundir_path "$run_dir" "$(cog::fn::executor::artifact_name stage2)")"
  stage3="$(cog::fn::rundir_path "$run_dir" "$(cog::fn::executor::artifact_name stage3)")"
  summary="$(cog::fn::rundir_path "$run_dir" "$(cog::fn::executor::artifact_name summary)")"

  jq -cn \
    --arg stage1_plan "$stage1" \
    --arg stage2_reviewed_plan "$stage2" \
    --arg stage3_execution "$stage3" \
    --arg summary "$summary" \
    '{stage1_plan: $stage1_plan, stage2_reviewed_plan: $stage2_reviewed_plan,
      stage3_execution: $stage3_execution, summary: $summary}'
}

cog::fn::executor::classify_input_json() {
  local input="${1:-}" plan_path="" stages_json

  [[ -n $input ]] || cog::fn::error_raise "MissingArgument" \
    "missing executor input" "function: cog::fn::executor::classify_input_json" "" \
    "pass a prompt or an existing .md plan path"

  if [[ $input == *.md && -f $input && -r $input ]]; then
    plan_path="$(realpath -- "$input")"
    stages_json='["stage2","stage3"]'
    jq -cn \
      --arg kind plan \
      --arg value "$input" \
      --arg plan_path "$plan_path" \
      --argjson stages "$stages_json" \
      '{kind: $kind, value: $value, plan_path: $plan_path, stages: $stages}'
    return 0
  fi

  stages_json='["stage1","stage2","stage3"]'
  jq -cn \
    --arg kind prompt \
    --arg value "$input" \
    --argjson stages "$stages_json" \
    '{kind: $kind, value: $value, plan_path: null, stages: $stages}'
}

cog::fn::executor::plan_engine_for_executor() {
  case "${1:-}" in
    claude)
      printf '%s\n' claude
      ;;
    codex-session)
      printf '%s\n' codex
      ;;
    *)
      cog::fn::error_raise "InvalidInput" \
        "unknown executor" "executor: ${1:-}" \
        "expected claude or codex-session" ""
      ;;
  esac
}

cog::fn::executor::select_reviewer_json() {
  case "${1:-}" in
    claude)
      jq -cn \
        --arg plan_engine claude \
        --arg review_engine codex \
        --arg reviewer /review-plan-lean \
        '{plan_engine: $plan_engine, review_engine: $review_engine, reviewer: $reviewer}'
      ;;
    codex)
      jq -cn \
        --arg plan_engine codex \
        --arg review_engine claude \
        --arg reviewer /review-plan-lean \
        '{plan_engine: $plan_engine, review_engine: $review_engine, reviewer: $reviewer}'
      ;;
    *)
      cog::fn::error_raise "InvalidInput" \
        "unknown plan engine" "plan-engine: ${1:-}" \
        "expected claude or codex" ""
      ;;
  esac
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
  local run_dir="${1:-}" executor="${2:-}" input_kind="${3:-}" plan_engine="${4:-}" reviewer="${5:-}"
  local stage1_status="${6:-}" stage2_status="${7:-}" stage3_status="${8:-}"
  local artifacts_json summary_path

  [[ -n $run_dir && -n $executor && -n $input_kind && -n $plan_engine && -n $reviewer ]] \
    || cog::fn::error_raise "MissingArgument" \
      "missing executor summary argument" \
      "function: cog::fn::executor::summary_json" "" \
      "pass run-dir, executor, input-kind, plan-engine, reviewer, and stage statuses"

  artifacts_json="$(cog::fn::executor::artifacts_json "$run_dir")"
  summary_path="$(jq -r '.summary' <<<"$artifacts_json")"

  jq -cn \
    --argjson ok true \
    --arg executor "$executor" \
    --arg run_dir "$run_dir" \
    --arg input_kind "$input_kind" \
    --arg plan_engine "$plan_engine" \
    --arg reviewer "$reviewer" \
    --arg stage1_status "$stage1_status" \
    --arg stage2_status "$stage2_status" \
    --arg stage3_status "$stage3_status" \
    --arg stage1_artifact "$(jq -r '.stage1_plan' <<<"$artifacts_json")" \
    --arg stage2_artifact "$(jq -r '.stage2_reviewed_plan' <<<"$artifacts_json")" \
    --arg stage3_artifact "$(jq -r '.stage3_execution' <<<"$artifacts_json")" \
    --arg summary "$summary_path" \
    '{
      schema: "cog.executor.summary.v1",
      ok: $ok,
      executor: $executor,
      run_dir: $run_dir,
      input_kind: $input_kind,
      plan_engine: $plan_engine,
      reviewer: $reviewer,
      stages: {
        stage1: {status: $stage1_status, artifact: $stage1_artifact},
        stage2: {status: $stage2_status, artifact: $stage2_artifact},
        stage3: {status: $stage3_status, artifact: $stage3_artifact}
      },
      artifacts: {summary: $summary}
    }'
}

cog::fn::executor::write_summary_json() {
  local run_dir="${1:-}" json summary_path

  json="$(cog::fn::executor::summary_json "$@")"
  summary_path="$(jq -r '.artifacts.summary' <<<"$json")"
  cog::fn::json_write_fragment "$summary_path" "$__cog_executor_summary_self_check" "$json"
}
