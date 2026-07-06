# shellcheck shell=bash
: 'desc: Parse plan-builder-to-queue arguments and create plan-vault run state.'

__cog_plan_builder_to_queue_setup_self_check='(.run_dir|type=="string") and (.repo_root|type=="string") and (.orientation_file|type=="string") and (.title|type=="string") and (.store|type=="string") and (.plan_root|type=="string") and (.plans_dir|type=="string") and (.queue_path|type=="string") and (.request_path|type=="string") and (.brief_body|type=="string") and (.brief_file|type=="string") and (.draft_path|type=="string") and (.review_path|type=="string") and (.work_dir|type=="string")'

__cog_plan_builder_to_queue_setup_usage() {
  cog::fn::ui_data "Usage: cog plan-builder-to-queue-setup [--json] [--title <text>] [--store auto|local|global] [arguments-string]"
}

# Consume only the leading --store/--title flags; keep the remaining orientation
# verbatim so it becomes the reviewer brief's verbatim base.
__cog_plan_builder_to_queue_setup_parse() {
  local raw="$1" out_store="$2" out_title="$3" out_orientation="$4"
  local parsed_store="" parsed_title="" rest="$raw" head value
  rest="${rest#"${rest%%[![:space:]]*}"}"
  while true; do
    head="${rest%%[[:space:]]*}"
    case "$head" in
      --store=*)
        parsed_store="${head#--store=}"
        rest="${rest#"$head"}"
        rest="${rest#"${rest%%[![:space:]]*}"}"
        ;;
      --store)
        rest="${rest#--store}"
        rest="${rest#"${rest%%[![:space:]]*}"}"
        value="${rest%%[[:space:]]*}"
        [[ -n $value && $value != --* ]] || cog::fn::error_raise_with_exit 2 "MissingArgument" \
          "missing store" "option: --store" "" "run 'cog plan-builder-to-queue-setup --help'"
        parsed_store="$value"
        rest="${rest#"$value"}"
        rest="${rest#"${rest%%[![:space:]]*}"}"
        ;;
      --title=*)
        parsed_title="${head#--title=}"
        rest="${rest#"$head"}"
        rest="${rest#"${rest%%[![:space:]]*}"}"
        ;;
      --title)
        rest="${rest#--title}"
        rest="${rest#"${rest%%[![:space:]]*}"}"
        # --title consumes the rest of the leading line up to the orientation; keep simple: one token.
        value="${rest%%[[:space:]]*}"
        [[ -n $value && $value != --* ]] || cog::fn::error_raise_with_exit 2 "MissingArgument" \
          "missing title" "option: --title" "" "run 'cog plan-builder-to-queue-setup --help'"
        parsed_title="$value"
        rest="${rest#"$value"}"
        rest="${rest#"${rest%%[![:space:]]*}"}"
        ;;
      --)
        rest="${rest#--}"
        rest="${rest#"${rest%%[![:space:]]*}"}"
        break
        ;;
      -?*)
        cog::fn::error_raise_with_exit 2 "InvalidInput" \
          "unknown plan-builder-to-queue flag" "option: $head" "" "expected --store or --title"
        ;;
      *)
        break
        ;;
    esac
  done
  [[ -n $rest ]] || cog::fn::error_raise_with_exit 2 "MissingArgument" \
    "orientation is required" "usage: cog plan-builder-to-queue-setup [--json] [arguments-string]" "" ""
  case "$parsed_store" in
    "" | auto | local | global) ;;
    *) cog::fn::error_raise_with_exit 2 "InvalidInput" \
      "invalid store" "option: --store ${parsed_store}" "expected auto, local, or global" "use --store auto|local|global" ;;
  esac
  printf -v "$out_store" '%s' "$parsed_store"
  printf -v "$out_title" '%s' "$parsed_title"
  printf -v "$out_orientation" '%s' "$rest"
}

__cog_plan_builder_to_queue_setup_build_json() {
  local raw="$1" title_override="${2:-}" store_override="${3:-}"
  local store title orientation run_dir repo_root orientation_file resolve_json
  local selected_store plan_root plans_dir queue_path first_line
  __cog_plan_builder_to_queue_setup_parse "$raw" store title orientation
  # Genuine top-level --title/--store flags take precedence over any in-string flags,
  # and carry multi-word values the single-token in-string parser cannot.
  [[ -n $title_override ]] && title="$title_override"
  if [[ -n $store_override ]]; then
    case "$store_override" in
      auto | local | global) store="$store_override" ;;
      *) cog::fn::error_raise_with_exit 2 "InvalidInput" \
        "invalid store" "option: --store ${store_override}" "expected auto, local, or global" "use --store auto|local|global" ;;
    esac
  fi
  run_dir="$(cog::fn::rundir_create plan-builder-to-queue)"
  repo_root="$(cog::fn::git_root)"
  orientation_file="${run_dir}/orientation.txt"
  printf '%s\n' "$orientation" >"$orientation_file" || cog::fn::error_raise "JsonWriteFailed" \
    "could not write orientation" "path: ${orientation_file}" "" "check run directory permissions"
  if [[ -z $title ]]; then
    first_line="${orientation%%$'\n'*}"
    first_line="${first_line#"${first_line%%[![:space:]]*}"}"
    title="${first_line:0:80}"
  fi
  [[ -n $title ]] || title="implementation plan"
  mkdir -p "${run_dir}/complexity-reports" "${run_dir}/split-verdicts" "${run_dir}/rounds-work" \
    || cog::fn::error_raise "TempDirCreateFailed" "could not create work dirs" "path: ${run_dir}" "" "check permissions"

  # Pre-flight: ensure the global vault exists git-by-default, then resolve the store.
  cog::fn::plan_store_init_global true
  resolve_json="$(cog::fn::plan_resolve_json "$repo_root" "$store" "")"
  selected_store="$(jq -r '.store' <<<"$resolve_json")"
  plan_root="$(jq -r '.plan_root' <<<"$resolve_json")"
  plans_dir="$(jq -r '.plans_dir' <<<"$resolve_json")"
  queue_path="$(jq -r '.queue_path' <<<"$resolve_json")"

  jq -n \
    --arg run_dir "$run_dir" \
    --arg repo_root "$repo_root" \
    --arg orientation_file "$orientation_file" \
    --arg title "$title" \
    --arg store "$selected_store" \
    --arg plan_root "$plan_root" \
    --arg plans_dir "$plans_dir" \
    --arg queue_path "$queue_path" \
    --arg request_path "$orientation_file" \
    --arg brief_body "${run_dir}/review-brief-body.md" \
    --arg brief_file "${run_dir}/review-brief.md" \
    --arg draft_path "${run_dir}/full-plan-draft.md" \
    --arg review_path "${run_dir}/review.md" \
    --arg work_dir "$run_dir" \
    --argjson resolve "$resolve_json" \
    '{run_dir: $run_dir, repo_root: $repo_root, orientation_file: $orientation_file,
      title: $title, store: $store, plan_root: $plan_root, plans_dir: $plans_dir,
      queue_path: $queue_path, request_path: $request_path, brief_body: $brief_body,
      brief_file: $brief_file, draft_path: $draft_path, review_path: $review_path,
      work_dir: $work_dir, resolve: $resolve}'
}

cog::cmd::plan_builder_to_queue_setup() {
  local mode=human raw="" title_override="" store_override="" have_raw=false json
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_plan_builder_to_queue_setup_usage
        return 0
        ;;
      --json)
        mode="json"
        shift
        ;;
      --title=*)
        title_override="${1#--title=}"
        shift
        ;;
      --title)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise_with_exit 2 "MissingArgument" \
          "missing title" "option: --title" "" "run 'cog plan-builder-to-queue-setup --help'"
        title_override="$2"
        shift 2
        ;;
      --store=*)
        store_override="${1#--store=}"
        shift
        ;;
      --store)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise_with_exit 2 "MissingArgument" \
          "missing store" "option: --store" "" "run 'cog plan-builder-to-queue-setup --help'"
        store_override="$2"
        shift 2
        ;;
      *)
        [[ $have_raw == false ]] || cog::fn::error_raise_with_exit 2 "TooManyArguments" \
          "too many arguments" "argument: $1" "" \
          "usage: cog plan-builder-to-queue-setup [--json] [--title <text>] [--store auto|local|global] [arguments-string]"
        raw="$1"
        have_raw=true
        shift
        ;;
    esac
  done
  json="$(__cog_plan_builder_to_queue_setup_build_json "$raw" "$title_override" "$store_override")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$__cog_plan_builder_to_queue_setup_self_check" "$json"
  else
    cog::fn::ui_data "RUN_DIR=$(jq -r '.run_dir' <<<"$json")"
    cog::fn::ui_data "REPO_ROOT=$(jq -r '.repo_root' <<<"$json")"
    cog::fn::ui_data "ORIENTATION_FILE=$(jq -r '.orientation_file' <<<"$json")"
    cog::fn::ui_data "TITLE=$(jq -r '.title' <<<"$json")"
    cog::fn::ui_data "STORE=$(jq -r '.store' <<<"$json")"
    cog::fn::ui_data "PLAN_ROOT=$(jq -r '.plan_root' <<<"$json")"
    cog::fn::ui_data "PLANS_DIR=$(jq -r '.plans_dir' <<<"$json")"
    cog::fn::ui_data "QUEUE_PATH=$(jq -r '.queue_path' <<<"$json")"
    cog::fn::ui_data "REQUEST_PATH=$(jq -r '.request_path' <<<"$json")"
    cog::fn::ui_data "BRIEF_BODY=$(jq -r '.brief_body' <<<"$json")"
    cog::fn::ui_data "BRIEF_FILE=$(jq -r '.brief_file' <<<"$json")"
    cog::fn::ui_data "DRAFT_PATH=$(jq -r '.draft_path' <<<"$json")"
    cog::fn::ui_data "REVIEW_PATH=$(jq -r '.review_path' <<<"$json")"
    cog::fn::ui_data "WORK_DIR=$(jq -r '.work_dir' <<<"$json")"
  fi
}
