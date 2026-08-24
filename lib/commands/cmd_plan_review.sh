# shellcheck shell=bash
: 'desc: Write, inspect, and validate annotated plan review artifacts.'

__cog_plan_review_self_check='(.ok|type=="boolean") and
  if .action == "items" then
    .schema == "cog.plan-review.items.v1" and (.path|type=="string") and (.count|type=="number") and (.items|type=="array")
  elif .action == "fold-check" then
    .schema == "cog.plan-review.fold-check.v1" and (.review_path|type=="string") and (.plan_path|type=="string") and (.manifest_path|type=="string") and (.review_sha256|type=="string") and (.plan_sha256|type=="string") and (.manifest_sha256|type=="string") and (.errors|type=="array")
  else
    .schema == "cog.plan-review.v1" and (.action|type=="string") and ((.run_dir|type=="string") or (.run_dir == null)) and (.output_path // .path | type=="string")
  end'

__cog_plan_review_usage() {
  cog::fn::ui_data "Usage: cog plan-review save --plan <abs.md> --request <abs.md> [--output <abs.md>] [--repo-root <abs>] [--research-root <dir>] [--json]"
  cog::fn::ui_data "Usage: cog plan-review orchestrator <input-plan-abs> <request-abs> <output-abs> [--json]"
  cog::fn::ui_data "Usage: cog plan-review validate <abs.md> [--json]"
  cog::fn::ui_data "Usage: cog plan-review items <review-abs.md> [--json]"
  cog::fn::ui_data "Usage: cog plan-review fold-check --review <review-abs.md> --plan <plan-abs.md> --manifest <manifest-abs.json> [--json]"
}

__cog_plan_review_items() {
  local path="" json_mode=false json item

  while (($# > 0)); do
    case "$1" in
      --json)
        json_mode=true
        shift
        ;;
      -*) cog::fn::error_raise "InvalidInput" \
        "unknown plan-review items option" "option: $1" "" "run 'cog plan-review --help'" ;;
      *)
        [[ -z $path ]] || cog::fn::error_raise "InvalidInput" \
          "too many plan-review items arguments" "argument: $1" "" "run 'cog plan-review --help'"
        path="$1"
        shift
        ;;
    esac
  done
  [[ -n $path ]] || cog::fn::error_raise "MissingArgument" \
    "missing plan-review path" "usage: cog plan-review items <review-abs.md>" "" "run 'cog plan-review --help'"
  json="$(cog::fn::plan_review::items_json "$path")"
  __cog_plan_review_emit "$json" "$json_mode" && return 0
  while IFS= read -r item; do
    cog::fn::ui_data "PLAN_REVIEW_ITEM=${item}"
  done < <(jq -c '.items[]' <<<"$json")
  cog::fn::ui_data "PLAN_REVIEW_ITEM_COUNT=$(jq -r '.count' <<<"$json")"
}

__cog_plan_review_fold_check() {
  local review="" plan="" manifest="" json_mode=false json

  while (($# > 0)); do
    case "$1" in
      --review | --plan | --manifest)
        local option="$1" value="${2:-}"
        [[ $# -ge 2 && -n $value ]] || cog::fn::error_raise "MissingArgument" \
          "missing plan-review fold-check value" "option: ${option}" "" "run 'cog plan-review --help'"
        case "$option" in
          --review)
            [[ -z $review ]] || cog::fn::error_raise "InvalidInput" "duplicate plan-review fold-check option" "option: --review" "" "run 'cog plan-review --help'"
            review="$value"
            ;;
          --plan)
            [[ -z $plan ]] || cog::fn::error_raise "InvalidInput" "duplicate plan-review fold-check option" "option: --plan" "" "run 'cog plan-review --help'"
            plan="$value"
            ;;
          --manifest)
            [[ -z $manifest ]] || cog::fn::error_raise "InvalidInput" "duplicate plan-review fold-check option" "option: --manifest" "" "run 'cog plan-review --help'"
            manifest="$value"
            ;;
        esac
        shift 2
        ;;
      --json)
        json_mode=true
        shift
        ;;
      -*) cog::fn::error_raise "InvalidInput" \
        "unknown plan-review fold-check option" "option: $1" "" "run 'cog plan-review --help'" ;;
      *) cog::fn::error_raise "InvalidInput" \
        "unexpected plan-review fold-check argument" "argument: $1" "" "run 'cog plan-review --help'" ;;
    esac
  done
  [[ -n $review && -n $plan && -n $manifest ]] || cog::fn::error_raise "MissingArgument" \
    "missing plan-review fold-check paths" "review, plan, and manifest are required" "" "run 'cog plan-review --help'"
  json="$(cog::fn::plan_review::fold_check_json "$review" "$plan" "$manifest")"
  if [[ $json_mode == true || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$__cog_plan_review_self_check" "$json"
    jq -e '.ok == true' <<<"$json" >/dev/null || return "$EX_DATAERR"
    return 0
  fi
  jq -e '.ok == true' <<<"$json" >/dev/null || cog::fn::error_raise "InvalidInput" \
    "plan review fold coverage failed" "review: ${review}" "$(jq -c '.errors' <<<"$json")" \
    "fix the fold manifest and rerun fold-check"
  cog::fn::ui_data "PLAN_REVIEW_FOLD_VALID total=$(jq -r '.counts.total' <<<"$json") folded=$(jq -r '.counts.folded' <<<"$json") waived=$(jq -r '.counts.waived' <<<"$json")"
}

__cog_plan_review_emit() {
  local json="$1"
  local json_mode="$2"

  if [[ $json_mode == true || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$__cog_plan_review_self_check" "$json"
    return 0
  fi
  return 1
}

__cog_plan_review_save() {
  local input_plan_path="" request_path="" output_override="" repo_root="" research_root_override=""
  local json_mode=false json output_path

  while (($# > 0)); do
    case "$1" in
      --plan)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" \
          "missing plan-review plan path" "option: --plan" "" "run 'cog plan-review --help'"
        input_plan_path="$2"
        shift 2
        ;;
      --request)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" \
          "missing plan-review request path" "option: --request" "" "run 'cog plan-review --help'"
        request_path="$2"
        shift 2
        ;;
      --output)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" \
          "missing plan-review output path" "option: --output" "" "run 'cog plan-review --help'"
        output_override="$2"
        shift 2
        ;;
      --repo-root)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" \
          "missing plan-review repo root" "option: --repo-root" "" "run 'cog plan-review --help'"
        repo_root="$2"
        shift 2
        ;;
      --research-root)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" \
          "missing plan-review research root" "option: --research-root" "" "run 'cog plan-review --help'"
        research_root_override="$2"
        shift 2
        ;;
      --json)
        json_mode=true
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown plan-review save option" "option: $1" "" "run 'cog plan-review --help'"
        ;;
      *)
        cog::fn::error_raise "InvalidInput" \
          "too many plan-review save arguments" "argument: $1" "" "run 'cog plan-review --help'"
        ;;
    esac
  done

  [[ -n $input_plan_path ]] || cog::fn::error_raise "MissingArgument" \
    "missing plan-review plan path" "option: --plan" "" "run 'cog plan-review --help'"
  [[ -n $request_path ]] || cog::fn::error_raise "MissingArgument" \
    "missing plan-review request path" "option: --request" "" "run 'cog plan-review --help'"
  if [[ -n $repo_root ]]; then
    cog::fn::plan_artifact::require_absolute_path "$repo_root" repo-root
  else
    repo_root="$(pwd -P)"
  fi
  json="$(cog::fn::plan_review::save_json "$input_plan_path" "$request_path" "$output_override" "$repo_root" "$research_root_override")"
  __cog_plan_review_emit "$json" "$json_mode" && return 0
  output_path="$(jq -r '.output_path' <<<"$json")"
  cog::fn::ui_data "PLAN_REVIEW_PATH=${output_path}"
}

__cog_plan_review_validate() {
  local path="" json_mode=false json

  while (($# > 0)); do
    case "$1" in
      --json)
        json_mode=true
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown plan-review validate option" "option: $1" "" "run 'cog plan-review --help'"
        ;;
      *)
        [[ -z $path ]] || cog::fn::error_raise "InvalidInput" \
          "too many plan-review validate arguments" "argument: $1" "" "run 'cog plan-review --help'"
        path="$1"
        shift
        ;;
    esac
  done

  [[ -n $path ]] || cog::fn::error_raise "MissingArgument" \
    "missing plan-review path" "usage: cog plan-review validate <abs.md>" "" \
    "run 'cog plan-review --help'"
  cog::fn::plan_artifact::require_absolute_path "$path" "plan-review"
  json="$(cog::fn::plan_review::validate_json "$path")"
  if [[ $json_mode == true || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$__cog_plan_review_self_check" "$json"
    jq -e '.ok == true' <<<"$json" >/dev/null || return "$EX_DATAERR"
    return 0
  fi
  jq -e '.ok == true' <<<"$json" >/dev/null || cog::fn::error_raise "InvalidInput" \
    "plan review failed validation" "path: ${path}" "$(jq -c '.errors' <<<"$json")" \
    "fix the plan review headings"
  cog::fn::ui_data "PLAN_REVIEW_VALID"
}

__cog_plan_review_orchestrator() {
  local input_plan_path="" request_path="" output_path="" json_mode=false json

  while (($# > 0)); do
    case "$1" in
      --json)
        json_mode=true
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown plan-review orchestrator option" "option: $1" "" "run 'cog plan-review --help'"
        ;;
      *)
        if [[ -z $input_plan_path ]]; then
          input_plan_path="$1"
        elif [[ -z $request_path ]]; then
          request_path="$1"
        elif [[ -z $output_path ]]; then
          output_path="$1"
        else
          cog::fn::error_raise "InvalidInput" \
            "too many plan-review orchestrator arguments" "argument: $1" "" \
            "run 'cog plan-review --help'"
        fi
        shift
        ;;
    esac
  done

  [[ -n $input_plan_path && -n $request_path && -n $output_path ]] || cog::fn::error_raise "MissingArgument" \
    "missing plan-review orchestrator paths" \
    "usage: cog plan-review orchestrator <input-plan-abs> <request-abs> <output-abs>" "" \
    "run 'cog plan-review --help'"
  json="$(cog::fn::plan_review::orchestrator_json "$input_plan_path" "$request_path" "$output_path")"
  __cog_plan_review_emit "$json" "$json_mode" && return 0
  cog::fn::ui_data "PLAN_REVIEW_PATH=${output_path}"
}

cog::cmd::plan_review() {
  local mode="${1:-}"

  case "$mode" in
    -h | --help)
      __cog_plan_review_usage
      ;;
    save)
      shift
      __cog_plan_review_save "$@"
      ;;
    orchestrator)
      shift
      __cog_plan_review_orchestrator "$@"
      ;;
    validate)
      shift
      __cog_plan_review_validate "$@"
      ;;
    items)
      shift
      __cog_plan_review_items "$@"
      ;;
    fold-check)
      shift
      __cog_plan_review_fold_check "$@"
      ;;
    "")
      cog::fn::error_raise "MissingArgument" \
        "missing plan-review mode" "usage: cog plan-review save|orchestrator|validate|items|fold-check" "" \
        "run 'cog plan-review --help'"
      ;;
    *)
      cog::fn::error_raise "InvalidInput" \
        "unknown plan-review mode" "mode: ${mode}" "" "run 'cog plan-review --help'"
      ;;
  esac
}
