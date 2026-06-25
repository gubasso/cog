# shellcheck shell=bash
: 'desc: Manage shared executor run contracts and stage artifacts.'

__cog_executor_init_self_check='(.schema=="cog.executor.init.v2") and (.ok==true) and (.run_dir|type=="string") and (.executor|type=="string") and (.engine|type=="string") and (.flow|type=="object") and (.stages|type=="array") and (.phases|type=="array") and (.artifacts.schema=="cog.executor.artifacts.v2")'
__cog_executor_queue_prompts_self_check='(.schema=="cog.executor.queue-prompts.v1") and (.prompts|type=="array")'
__cog_executor_artifacts_self_check='(.schema=="cog.executor.artifacts.v2") and (.phases|type=="array") and (.summary|type=="string")'
__cog_executor_classify_self_check='(.kind=="prompt" or .kind=="plan") and has("plan_path") and (has("stages")|not)'
__cog_executor_prepare_step_self_check='(.schema=="cog.executor.prepare-step.v1") and (.producer|type=="string") and (.prepare_engine|type=="string") and (.lane|type=="string")'
__cog_executor_adopt_prepared_self_check='(.schema=="cog.executor.adopt-prepared.v1") and (.ok==true) and (.path|type=="string")'

__cog_executor_usage() {
  cog::fn::ui_data "Usage: cog executor init --executor <executor-vetted|executor-oneshot> --engine <claude|codex> --input <prompt-or-plan> [--json]"
  cog::fn::ui_data "Usage: cog executor classify-input <input> [--json]"
  cog::fn::ui_data "Usage: cog executor prepare-step --executor <executor-vetted|executor-oneshot> --engine <claude|codex> --route <needs-plan|good-input> [--json]"
  cog::fn::ui_data "Usage: cog executor adopt-prepared --run-dir <dir> --from <path> [--json]"
  cog::fn::ui_data "Usage: cog executor artifacts <run-dir> [--json]"
  cog::fn::ui_data "Usage: cog executor summary --run-dir <dir> --executor <executor-vetted|executor-oneshot> --engine <claude|codex> --route <needs-plan|good-input> --stage1 <done|failed> --stage2 <done|failed> [--json]"
  cog::fn::ui_data "Usage: cog executor queue-prompts [--json]"
  cog::fn::ui_data "Input classification: an existing readable regular .md file is a plan; everything else, including a missing .md path, is a prompt. The input-quality route (needs-plan|good-input) is the assess-input verdict, independent of input kind."
}

__cog_executor_validate_stage_status() {
  local ordinal="$1" value="${2:-}"
  case "$value" in
    done | failed) return 0 ;;
    *) cog::fn::error_raise "InvalidInput" "invalid executor stage status" "${ordinal}: ${value}" \
      "expected done or failed" "" ;;
  esac
}

__cog_executor_emit_stages_line() {
  jq -r '.stages | join(",")' <<<"$1"
}

__cog_executor_init_write_state() {
  local run_dir="$1" executor="$2" engine="$3" classify_json="$4"
  local input_kind value plan_path

  printf '%s\n' "$executor" >"$(cog::fn::rundir_path "$run_dir" executor)" \
    || cog::fn::error_raise "JsonWriteFailed" "could not write executor state" \
      "path: $(cog::fn::rundir_path "$run_dir" executor)" "" "check run directory permissions"
  printf '%s\n' "$engine" >"$(cog::fn::rundir_path "$run_dir" engine)" \
    || cog::fn::error_raise "JsonWriteFailed" "could not write executor engine state" \
      "path: $(cog::fn::rundir_path "$run_dir" engine)" "" "check run directory permissions"

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
  local executor="" engine="" input="" json="${COG_UI_JSON:-false}"
  local classify_json input_kind run_dir artifacts_json init_json flow_json stages_json phases_json

  while (($# > 0)); do
    case "$1" in
      --executor)
        [[ $# -ge 2 && -n ${2:-} && -z $executor ]] || cog::fn::error_raise "MissingArgument" \
          "missing executor" "option: --executor" "" "run 'cog executor --help'"
        executor="$2"
        shift 2
        ;;
      --engine)
        [[ $# -ge 2 && -n ${2:-} && -z $engine ]] || cog::fn::error_raise "MissingArgument" \
          "missing executor engine" "option: --engine" "" "run 'cog executor --help'"
        engine="$2"
        shift 2
        ;;
      --input)
        [[ $# -ge 2 && -n ${2:-} && -z $input ]] || cog::fn::error_raise "MissingArgument" \
          "missing executor input" "option: --input" "" "run 'cog executor --help'"
        input="$2"
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

  [[ -n $executor && -n $engine && -n $input ]] || cog::fn::error_raise "MissingArgument" \
    "missing executor init argument" \
    "usage: cog executor init --executor <executor-vetted|executor-oneshot> --engine <claude|codex> --input <prompt-or-plan>" "" \
    "run 'cog executor --help'"
  flow_json="$(cog::fn::executor::flow_json "$executor")"
  cog::fn::executor::validate_engine_for_executor "$executor" "$engine"
  classify_json="$(cog::fn::executor::classify_input_json "$input")"
  input_kind="$(jq -r '.kind' <<<"$classify_json")"
  stages_json="$(cog::fn::executor::stages_json "$executor")"
  run_dir="$(cog::fn::rundir_create "${executor}-${engine}")"
  __cog_executor_init_write_state "$run_dir" "$executor" "$engine" "$classify_json"
  artifacts_json="$(cog::fn::executor::artifacts_json "$run_dir")"
  phases_json="$(jq -c '.phases' <<<"$artifacts_json")"
  init_json="$(jq -cn \
    --arg schema "cog.executor.init.v2" \
    --argjson ok true \
    --arg action init \
    --arg executor "$executor" \
    --arg engine "$engine" \
    --arg run_dir "$run_dir" \
    --argjson input_obj "$(jq -c '{kind, value, plan_path}' <<<"$classify_json")" \
    --argjson flow "$flow_json" \
    --argjson stages "$stages_json" \
    --argjson phases "$phases_json" \
    --argjson artifacts "$artifacts_json" \
    '{schema: $schema, ok: $ok, action: $action, executor: $executor, engine: $engine, run_dir: $run_dir,
      input: $input_obj, flow: $flow, stages: $stages, phases: $phases, artifacts: $artifacts}')"

  if [[ $json == true ]]; then
    cog::fn::json_emit "$__cog_executor_init_self_check" "$init_json"
  else
    cog::fn::ui_data "RUN_DIR=${run_dir}"
    cog::fn::ui_data "INPUT_KIND=${input_kind}"
    cog::fn::ui_data "EXECUTOR=${executor}"
    cog::fn::ui_data "ENGINE=${engine}"
    cog::fn::ui_data "STAGES=$(__cog_executor_emit_stages_line "$init_json")"
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
  fi
}

__cog_executor_prepare_step() {
  local executor="" engine="" route="" json="${COG_UI_JSON:-false}" result

  while (($# > 0)); do
    case "$1" in
      --executor)
        [[ $# -ge 2 && -n ${2:-} && -z $executor ]] || cog::fn::error_raise "MissingArgument" \
          "missing executor" "option: --executor" "" "run 'cog executor --help'"
        executor="$2"
        shift 2
        ;;
      --engine)
        [[ $# -ge 2 && -n ${2:-} && -z $engine ]] || cog::fn::error_raise "MissingArgument" \
          "missing executor engine" "option: --engine" "" "run 'cog executor --help'"
        engine="$2"
        shift 2
        ;;
      --route)
        [[ $# -ge 2 && -n ${2:-} && -z $route ]] || cog::fn::error_raise "MissingArgument" \
          "missing route" "option: --route" "" "run 'cog executor --help'"
        route="$2"
        shift 2
        ;;
      --json)
        json=true
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" "unknown prepare-step option" "option: $1" "" "run 'cog executor --help'"
        ;;
      *)
        cog::fn::error_raise "TooManyArguments" "too many prepare-step arguments" "argument: $1" "" "run 'cog executor --help'"
        ;;
    esac
  done

  [[ -n $executor && -n $engine && -n $route ]] || cog::fn::error_raise "MissingArgument" \
    "missing prepare-step argument" \
    "usage: cog executor prepare-step --executor <executor> --engine <engine> --route <needs-plan|good-input>" "" \
    "run 'cog executor --help'"
  result="$(cog::fn::executor::prepare_step_json "$executor" "$engine" "$route")"
  if [[ $json == true ]]; then
    cog::fn::json_emit "$__cog_executor_prepare_step_self_check" "$result"
  else
    cog::fn::ui_data "PRODUCER=$(jq -r '.producer' <<<"$result")"
    cog::fn::ui_data "PREPARE_ENGINE=$(jq -r '.prepare_engine' <<<"$result")"
    cog::fn::ui_data "LANE=$(jq -r '.lane' <<<"$result")"
    cog::fn::ui_data "ARTIFACT=$(jq -r '.artifact' <<<"$result")"
  fi
}

__cog_executor_adopt_prepared() {
  local run_dir="" from="" json="${COG_UI_JSON:-false}" result

  while (($# > 0)); do
    case "$1" in
      --run-dir)
        [[ $# -ge 2 && -n ${2:-} && -z $run_dir ]] || cog::fn::error_raise "MissingArgument" \
          "missing run directory" "option: --run-dir" "" "run 'cog executor --help'"
        run_dir="$2"
        shift 2
        ;;
      --from)
        [[ $# -ge 2 && -n ${2:-} && -z $from ]] || cog::fn::error_raise "MissingArgument" \
          "missing source path" "option: --from" "" "run 'cog executor --help'"
        from="$2"
        shift 2
        ;;
      --json)
        json=true
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" "unknown adopt-prepared option" "option: $1" "" "run 'cog executor --help'"
        ;;
      *)
        cog::fn::error_raise "TooManyArguments" "too many adopt-prepared arguments" "argument: $1" "" "run 'cog executor --help'"
        ;;
    esac
  done

  [[ -n $run_dir && -n $from ]] || cog::fn::error_raise "MissingArgument" \
    "missing adopt-prepared argument" \
    "usage: cog executor adopt-prepared --run-dir <dir> --from <path>" "" \
    "run 'cog executor --help'"
  result="$(cog::fn::executor::adopt_prepared_json "$run_dir" "$from")"
  if [[ $json == true ]]; then
    cog::fn::json_emit "$__cog_executor_adopt_prepared_self_check" "$result"
  else
    cog::fn::ui_data "PREPARED_PLAN=$(jq -r '.path' <<<"$result")"
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
    jq -r '.phases[] | [.ordinal, .path] | @tsv' <<<"$result" | while IFS=$'\t' read -r ordinal path; do
      cog::fn::ui_data "PHASE_$(tr '[:lower:]' '[:upper:]' <<<"$ordinal")=${path}"
    done
    cog::fn::ui_data "EXECUTOR_SUMMARY=$(jq -r '.summary' <<<"$result")"
  fi
}

__cog_executor_summary() {
  local run_dir="" executor="" engine="" route="" stage1="" stage2=""
  local json="${COG_UI_JSON:-false}" flow_json summary_json summary_path
  local -a summary_args=()

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
      --engine)
        [[ $# -ge 2 && -n ${2:-} && -z $engine ]] || cog::fn::error_raise "MissingArgument" \
          "missing executor engine" "option: --engine" "" "run 'cog executor --help'"
        engine="$2"
        shift 2
        ;;
      --route)
        [[ $# -ge 2 && -n ${2:-} && -z $route ]] || cog::fn::error_raise "MissingArgument" \
          "missing route" "option: --route" "" "run 'cog executor --help'"
        route="$2"
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

  [[ -n $run_dir && -n $executor && -n $engine && -n $route ]] \
    || cog::fn::error_raise "MissingArgument" \
      "missing summary argument" \
      "usage: cog executor summary --run-dir <dir> --executor <executor> --engine <engine> --route <needs-plan|good-input> --stage1 <status> --stage2 <status>" "" \
      "run 'cog executor --help'"
  [[ -d $run_dir ]] || cog::fn::error_raise "InputNotFound" \
    "executor run directory not found" "path: ${run_dir}" "" "check --run-dir"
  flow_json="$(cog::fn::executor::flow_json "$executor")"
  cog::fn::executor::validate_engine_for_executor "$executor" "$engine"
  cog::fn::executor::validate_route "$route"

  while IFS= read -r ordinal; do
    case "$ordinal" in
      stage1) status="$stage1" ;;
      stage2) status="$stage2" ;;
      *) status="" ;;
    esac
    [[ -n $status ]] || cog::fn::error_raise "MissingArgument" \
      "missing executor stage status" "stage: ${ordinal}" \
      "required by executor ${executor}" \
      "pass --${ordinal} <status>"
    __cog_executor_validate_stage_status "$ordinal" "$status"
    summary_args+=("${ordinal}=${status}")
  done < <(jq -r '.phases[].ordinal' <<<"$flow_json")

  if [[ $json == true ]]; then
    # File-first write still happens, but stdout must be pure JSON: suppress the
    # RESOLVED line that write_summary_json (via json_write_fragment) prints.
    cog::fn::executor::write_summary_json "$run_dir" "$executor" "$engine" "$route" "${summary_args[@]}" >/dev/null
    summary_path="$(cog::fn::rundir_path "$run_dir" "$(cog::fn::executor::artifact_name "$executor" summary)")"
    summary_json="$(<"$summary_path")"
    cog::fn::json_emit "$(cog::fn::executor::summary_self_check)" "$summary_json"
  else
    cog::fn::executor::write_summary_json "$run_dir" "$executor" "$engine" "$route" "${summary_args[@]}"
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
    prepare-step)
      shift
      __cog_executor_prepare_step "$@"
      ;;
    adopt-prepared)
      shift
      __cog_executor_adopt_prepared "$@"
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
        "missing executor mode" "usage: cog executor init|classify-input|prepare-step|adopt-prepared|artifacts|summary|queue-prompts" "" \
        "run 'cog executor --help'"
      ;;
    *)
      cog::fn::error_raise "InvalidInput" \
        "unknown executor mode" "mode: ${mode}" "" "run 'cog executor --help'"
      ;;
  esac
}
