# shellcheck shell=bash
: 'desc: Manage shared executor run contracts and stage artifacts.'

__cog_executor_init_self_check='(.schema=="cog.executor.init.v1") and (.ok==true) and (.run_dir|type=="string")'
__cog_executor_queue_prompts_self_check='(.schema=="cog.executor.queue-prompts.v1") and (.prompts|type=="array")'
__cog_executor_artifacts_self_check='(.stage1_plan|type=="string") and (.stage2_reviewed_plan|type=="string") and (.stage3_execution|type=="string") and (.summary|type=="string")'
__cog_executor_classify_self_check='(.kind=="prompt" or .kind=="plan") and (.stages|type=="array") and has("plan_path")'
__cog_executor_reviewer_self_check='(.plan_engine|type=="string") and (.review_engine|type=="string") and (.reviewer|type=="string")'

__cog_executor_usage() {
  cog::fn::ui_data "Usage: cog executor init --executor <claude|codex-session> --input <prompt-or-plan> [--plan-engine <claude|codex>] [--json]"
  cog::fn::ui_data "Usage: cog executor classify-input <input> [--json]"
  cog::fn::ui_data "Usage: cog executor select-reviewer --plan-engine <claude|codex> [--json]"
  cog::fn::ui_data "Usage: cog executor artifacts <run-dir> [--json]"
  cog::fn::ui_data "Usage: cog executor summary --run-dir <dir> --executor <claude|codex-session> --input-kind <prompt|plan> --plan-engine <claude|codex> --reviewer <slash-command> --stage1 <skipped|done|failed> --stage2 <done|failed> --stage3 <done|failed> [--json]"
  cog::fn::ui_data "Usage: cog executor queue-prompts [--json]"
  cog::fn::ui_data "Input classification: an existing readable regular .md file is a plan; everything else, including a missing .md path, is a prompt."
}

__cog_executor_validate_executor() {
  cog::fn::executor::plan_engine_for_executor "${1:-}" >/dev/null
}

__cog_executor_validate_input_kind() {
  case "${1:-}" in
    prompt | plan) return 0 ;;
    *) cog::fn::error_raise "InvalidInput" "invalid executor input kind" "input-kind: ${1:-}" "expected prompt or plan" "" ;;
  esac
}

__cog_executor_validate_stage1_status() {
  case "${1:-}" in
    skipped | done | failed) return 0 ;;
    *) cog::fn::error_raise "InvalidInput" "invalid executor stage1 status" "stage1: ${1:-}" "expected skipped, done, or failed" "" ;;
  esac
}

__cog_executor_validate_stage_status() {
  local label="$1" value="${2:-}"
  case "$value" in
    done | failed) return 0 ;;
    *) cog::fn::error_raise "InvalidInput" "invalid executor stage status" "${label}: ${value}" "expected done or failed" "" ;;
  esac
}

__cog_executor_validate_reviewer() {
  case "${1:-}" in
    /review-plan-claude | /review-plan-codex) return 0 ;;
    *) cog::fn::error_raise "InvalidInput" "invalid executor reviewer" "reviewer: ${1:-}" "expected /review-plan-claude or /review-plan-codex" "" ;;
  esac
}

__cog_executor_emit_stages_line() {
  jq -r '.stages | join(",")' <<<"$1"
}

__cog_executor_init_write_state() {
  local run_dir="$1" classify_json="$2"
  local input_kind value plan_path

  input_kind="$(jq -r '.kind' <<<"$classify_json")"
  value="$(jq -r '.value' <<<"$classify_json")"
  printf '%s\n' "$input_kind" >"$(cog::fn::rundir_path "$run_dir" input-kind)" \
    || cog::fn::error_raise "JsonWriteFailed" "could not write executor input kind" \
      "path: $(cog::fn::rundir_path "$run_dir" input-kind)" "" "check run directory permissions"

  case "$input_kind" in
    prompt)
      printf '%s\n' "$value" >"$(cog::fn::rundir_path "$run_dir" request.md)" \
        || cog::fn::error_raise "JsonWriteFailed" "could not write executor request" \
          "path: $(cog::fn::rundir_path "$run_dir" request.md)" "" "check run directory permissions"
      ;;
    plan)
      plan_path="$(jq -r '.plan_path' <<<"$classify_json")"
      printf '%s\n' "$plan_path" >"$(cog::fn::rundir_path "$run_dir" plan-source)" \
        || cog::fn::error_raise "JsonWriteFailed" "could not write executor plan source" \
          "path: $(cog::fn::rundir_path "$run_dir" plan-source)" "" "check run directory permissions"
      ;;
  esac
}

__cog_executor_init() {
  local executor="" input="" plan_engine="" json="${COG_UI_JSON:-false}"
  local classify_json input_kind run_dir reviewer_json reviewer artifacts_json init_json

  while (($# > 0)); do
    case "$1" in
      --executor)
        [[ $# -ge 2 && -n ${2:-} && -z $executor ]] || cog::fn::error_raise "MissingArgument" \
          "missing executor" "option: --executor" "" "run 'cog executor --help'"
        executor="$2"
        shift 2
        ;;
      --input)
        [[ $# -ge 2 && -n ${2:-} && -z $input ]] || cog::fn::error_raise "MissingArgument" \
          "missing executor input" "option: --input" "" "run 'cog executor --help'"
        input="$2"
        shift 2
        ;;
      --plan-engine)
        [[ $# -ge 2 && -n ${2:-} && -z $plan_engine ]] || cog::fn::error_raise "MissingArgument" \
          "missing plan engine" "option: --plan-engine" "" "run 'cog executor --help'"
        plan_engine="$2"
        shift 2
        ;;
      --json)
        json=true
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" "unknown executor init option" "option: $1" "" "run 'cog executor --help'"
        ;;
      *)
        cog::fn::error_raise "TooManyArguments" "too many executor init arguments" "argument: $1" "" "run 'cog executor --help'"
        ;;
    esac
  done

  [[ -n $executor && -n $input ]] || cog::fn::error_raise "MissingArgument" \
    "missing executor init argument" \
    "usage: cog executor init --executor <claude|codex-session> --input <prompt-or-plan>" "" \
    "run 'cog executor --help'"
  __cog_executor_validate_executor "$executor"
  classify_json="$(cog::fn::executor::classify_input_json "$input")"
  input_kind="$(jq -r '.kind' <<<"$classify_json")"
  if [[ $input_kind == plan ]]; then
    [[ -n $plan_engine ]] || cog::fn::error_raise "MissingArgument" \
      "plan input requires --plan-engine" "input: ${input}" \
      "the file path alone cannot prove which engine produced the plan" \
      "pass --plan-engine claude or --plan-engine codex"
  else
    plan_engine="$(cog::fn::executor::plan_engine_for_executor "$executor")"
  fi
  reviewer_json="$(cog::fn::executor::select_reviewer_json "$plan_engine")"
  reviewer="$(jq -r '.reviewer' <<<"$reviewer_json")"
  run_dir="$(cog::fn::rundir_create "executor-${executor}")"
  __cog_executor_init_write_state "$run_dir" "$classify_json"
  artifacts_json="$(cog::fn::executor::artifacts_json "$run_dir")"
  init_json="$(jq -cn \
    --arg schema "cog.executor.init.v1" \
    --argjson ok true \
    --arg action init \
    --arg executor "$executor" \
    --arg run_dir "$run_dir" \
    --argjson input_obj "$(jq -c '{kind, value, plan_path}' <<<"$classify_json")" \
    --arg plan_engine "$plan_engine" \
    --arg reviewer "$reviewer" \
    --argjson stages "$(jq -c '.stages' <<<"$classify_json")" \
    --argjson artifacts "$artifacts_json" \
    '{schema: $schema, ok: $ok, action: $action, executor: $executor, run_dir: $run_dir,
      input: $input_obj, plan_engine: $plan_engine, reviewer: $reviewer, stages: $stages,
      artifacts: $artifacts}')"

  if [[ $json == true ]]; then
    cog::fn::json_emit "$__cog_executor_init_self_check" "$init_json"
  else
    cog::fn::ui_data "RUN_DIR=${run_dir}"
    cog::fn::ui_data "INPUT_KIND=${input_kind}"
    cog::fn::ui_data "PLAN_ENGINE=${plan_engine}"
    cog::fn::ui_data "REVIEWER=${reviewer}"
    cog::fn::ui_data "STAGES=$(__cog_executor_emit_stages_line "$classify_json")"
    cog::fn::ui_data "SUMMARY_PATH=$(jq -r '.summary' <<<"$artifacts_json")"
  fi
}

__cog_executor_classify_input() {
  local input="" json="${COG_UI_JSON:-false}" result plan_path

  while (($# > 0)); do
    case "$1" in
      --json)
        json=true
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" "unknown classify-input option" "option: $1" "" "run 'cog executor --help'"
        ;;
      *)
        [[ -z $input ]] || cog::fn::error_raise "TooManyArguments" \
          "too many classify-input arguments" "argument: $1" "" "run 'cog executor --help'"
        input="$1"
        shift
        ;;
    esac
  done

  [[ -n $input ]] || cog::fn::error_raise "MissingArgument" \
    "missing classify-input input" "usage: cog executor classify-input <input> [--json]" "" \
    "run 'cog executor --help'"
  result="$(cog::fn::executor::classify_input_json "$input")"
  if [[ $json == true ]]; then
    cog::fn::json_emit "$__cog_executor_classify_self_check" "$result"
  else
    plan_path="$(jq -r '.plan_path // ""' <<<"$result")"
    cog::fn::ui_data "INPUT_KIND=$(jq -r '.kind' <<<"$result")"
    cog::fn::ui_data "PLAN_PATH=${plan_path}"
    cog::fn::ui_data "STAGES=$(__cog_executor_emit_stages_line "$result")"
  fi
}

__cog_executor_select_reviewer() {
  local plan_engine="" json="${COG_UI_JSON:-false}" result

  while (($# > 0)); do
    case "$1" in
      --plan-engine)
        [[ $# -ge 2 && -n ${2:-} && -z $plan_engine ]] || cog::fn::error_raise "MissingArgument" \
          "missing plan engine" "option: --plan-engine" "" "run 'cog executor --help'"
        plan_engine="$2"
        shift 2
        ;;
      --json)
        json=true
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" "unknown select-reviewer option" "option: $1" "" "run 'cog executor --help'"
        ;;
      *)
        cog::fn::error_raise "TooManyArguments" "too many select-reviewer arguments" "argument: $1" "" "run 'cog executor --help'"
        ;;
    esac
  done

  [[ -n $plan_engine ]] || cog::fn::error_raise "MissingArgument" \
    "missing plan engine" "usage: cog executor select-reviewer --plan-engine <claude|codex>" "" \
    "run 'cog executor --help'"
  result="$(cog::fn::executor::select_reviewer_json "$plan_engine")"
  if [[ $json == true ]]; then
    cog::fn::json_emit "$__cog_executor_reviewer_self_check" "$result"
  else
    cog::fn::ui_data "PLAN_ENGINE=$(jq -r '.plan_engine' <<<"$result")"
    cog::fn::ui_data "REVIEW_ENGINE=$(jq -r '.review_engine' <<<"$result")"
    cog::fn::ui_data "REVIEWER=$(jq -r '.reviewer' <<<"$result")"
  fi
}

__cog_executor_artifacts() {
  local run_dir="" json="${COG_UI_JSON:-false}" result

  while (($# > 0)); do
    case "$1" in
      --json)
        json=true
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" "unknown artifacts option" "option: $1" "" "run 'cog executor --help'"
        ;;
      *)
        [[ -z $run_dir ]] || cog::fn::error_raise "TooManyArguments" \
          "too many artifacts arguments" "argument: $1" "" "run 'cog executor --help'"
        run_dir="$1"
        shift
        ;;
    esac
  done

  [[ -n $run_dir ]] || cog::fn::error_raise "MissingArgument" \
    "missing run directory" "usage: cog executor artifacts <run-dir> [--json]" "" \
    "run 'cog executor --help'"
  result="$(cog::fn::executor::artifacts_json "$run_dir")"
  if [[ $json == true ]]; then
    cog::fn::json_emit "$__cog_executor_artifacts_self_check" "$result"
  else
    cog::fn::ui_data "STAGE1_PLAN=$(jq -r '.stage1_plan' <<<"$result")"
    cog::fn::ui_data "STAGE2_REVIEWED_PLAN=$(jq -r '.stage2_reviewed_plan' <<<"$result")"
    cog::fn::ui_data "STAGE3_EXECUTION=$(jq -r '.stage3_execution' <<<"$result")"
    cog::fn::ui_data "EXECUTOR_SUMMARY=$(jq -r '.summary' <<<"$result")"
  fi
}

__cog_executor_summary() {
  local run_dir="" executor="" input_kind="" plan_engine="" reviewer="" stage1="" stage2="" stage3=""
  local json="${COG_UI_JSON:-false}" summary_json summary_path

  while (($# > 0)); do
    case "$1" in
      --run-dir)
        [[ $# -ge 2 && -n ${2:-} && -z $run_dir ]] || cog::fn::error_raise "MissingArgument" \
          "missing run directory" "option: --run-dir" "" "run 'cog executor --help'"
        run_dir="$2"
        shift 2
        ;;
      --executor)
        [[ $# -ge 2 && -n ${2:-} && -z $executor ]] || cog::fn::error_raise "MissingArgument" \
          "missing executor" "option: --executor" "" "run 'cog executor --help'"
        executor="$2"
        shift 2
        ;;
      --input-kind)
        [[ $# -ge 2 && -n ${2:-} && -z $input_kind ]] || cog::fn::error_raise "MissingArgument" \
          "missing input kind" "option: --input-kind" "" "run 'cog executor --help'"
        input_kind="$2"
        shift 2
        ;;
      --plan-engine)
        [[ $# -ge 2 && -n ${2:-} && -z $plan_engine ]] || cog::fn::error_raise "MissingArgument" \
          "missing plan engine" "option: --plan-engine" "" "run 'cog executor --help'"
        plan_engine="$2"
        shift 2
        ;;
      --reviewer)
        [[ $# -ge 2 && -n ${2:-} && -z $reviewer ]] || cog::fn::error_raise "MissingArgument" \
          "missing reviewer" "option: --reviewer" "" "run 'cog executor --help'"
        reviewer="$2"
        shift 2
        ;;
      --stage1)
        [[ $# -ge 2 && -n ${2:-} && -z $stage1 ]] || cog::fn::error_raise "MissingArgument" \
          "missing stage1 status" "option: --stage1" "" "run 'cog executor --help'"
        stage1="$2"
        shift 2
        ;;
      --stage2)
        [[ $# -ge 2 && -n ${2:-} && -z $stage2 ]] || cog::fn::error_raise "MissingArgument" \
          "missing stage2 status" "option: --stage2" "" "run 'cog executor --help'"
        stage2="$2"
        shift 2
        ;;
      --stage3)
        [[ $# -ge 2 && -n ${2:-} && -z $stage3 ]] || cog::fn::error_raise "MissingArgument" \
          "missing stage3 status" "option: --stage3" "" "run 'cog executor --help'"
        stage3="$2"
        shift 2
        ;;
      --json)
        json=true
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" "unknown summary option" "option: $1" "" "run 'cog executor --help'"
        ;;
      *)
        cog::fn::error_raise "TooManyArguments" "too many summary arguments" "argument: $1" "" "run 'cog executor --help'"
        ;;
    esac
  done

  [[ -n $run_dir && -n $executor && -n $input_kind && -n $plan_engine && -n $reviewer && -n $stage1 && -n $stage2 && -n $stage3 ]] \
    || cog::fn::error_raise "MissingArgument" \
      "missing summary argument" \
      "usage: cog executor summary --run-dir <dir> --executor <executor> --input-kind <prompt|plan> --plan-engine <engine> --reviewer <slash-command> --stage1 <status> --stage2 <status> --stage3 <status>" "" \
      "run 'cog executor --help'"
  [[ -d $run_dir ]] || cog::fn::error_raise "InputNotFound" \
    "executor run directory not found" "path: ${run_dir}" "" "check --run-dir"
  __cog_executor_validate_executor "$executor"
  __cog_executor_validate_input_kind "$input_kind"
  __cog_executor_validate_reviewer "$reviewer"
  # Enforce the OTHER-engine table: the reviewer must be the one the plan-engine selects.
  local expected_reviewer
  expected_reviewer="$(cog::fn::executor::select_reviewer_json "$plan_engine" | jq -r '.reviewer')"
  [[ $reviewer == "$expected_reviewer" ]] || cog::fn::error_raise "InvalidInput" \
    "reviewer does not match the other-engine table" \
    "plan-engine: ${plan_engine}, reviewer: ${reviewer}" \
    "plan-engine ${plan_engine} must be reviewed by ${expected_reviewer}" \
    "pass --reviewer ${expected_reviewer}"
  __cog_executor_validate_stage1_status "$stage1"
  __cog_executor_validate_stage_status stage2 "$stage2"
  __cog_executor_validate_stage_status stage3 "$stage3"

  if [[ $json == true ]]; then
    # File-first write still happens, but stdout must be pure JSON: suppress the
    # RESOLVED line that write_summary_json (via json_write_fragment) prints.
    cog::fn::executor::write_summary_json "$run_dir" "$executor" "$input_kind" "$plan_engine" "$reviewer" "$stage1" "$stage2" "$stage3" >/dev/null
    summary_path="$(cog::fn::rundir_path "$run_dir" "$(cog::fn::executor::artifact_name summary)")"
    summary_json="$(<"$summary_path")"
    cog::fn::json_emit "$(cog::fn::executor::summary_self_check)" "$summary_json"
  else
    cog::fn::executor::write_summary_json "$run_dir" "$executor" "$input_kind" "$plan_engine" "$reviewer" "$stage1" "$stage2" "$stage3"
  fi
}

__cog_executor_queue_prompts() {
  local json="${COG_UI_JSON:-false}" result

  while (($# > 0)); do
    case "$1" in
      --json)
        json=true
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" "unknown queue-prompts option" "option: $1" "" "run 'cog executor --help'"
        ;;
      *)
        cog::fn::error_raise "TooManyArguments" "too many queue-prompts arguments" "argument: $1" "" "run 'cog executor --help'"
        ;;
    esac
  done

  result="$(cog::fn::executor::queue_prompts_json)"
  if [[ $json == true ]]; then
    cog::fn::json_emit "$__cog_executor_queue_prompts_self_check" "$result"
  else
    jq -r '.prompts[] | "QUEUE_PROMPT=" + .slash' <<<"$result" | while IFS= read -r line; do
      cog::fn::ui_data "$line"
    done
  fi
}

cog::cmd::executor() {
  local mode="${1:-}"

  case "$mode" in
    -h | --help)
      __cog_executor_usage
      ;;
    init)
      shift
      __cog_executor_init "$@"
      ;;
    classify-input)
      shift
      __cog_executor_classify_input "$@"
      ;;
    select-reviewer)
      shift
      __cog_executor_select_reviewer "$@"
      ;;
    artifacts)
      shift
      __cog_executor_artifacts "$@"
      ;;
    summary)
      shift
      __cog_executor_summary "$@"
      ;;
    queue-prompts)
      shift
      __cog_executor_queue_prompts "$@"
      ;;
    "")
      cog::fn::error_raise "MissingArgument" \
        "missing executor mode" "usage: cog executor init|classify-input|select-reviewer|artifacts|summary|queue-prompts" "" \
        "run 'cog executor --help'"
      ;;
    *)
      cog::fn::error_raise "InvalidInput" \
        "unknown executor mode" "mode: ${mode}" "" "run 'cog executor --help'"
      ;;
  esac
}
