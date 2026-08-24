# shellcheck shell=bash
: 'desc: Parse review-plan-multi arguments and create run state.'

__cog_review_plan_multi_setup_self_check='(.run_dir|type=="string") and (.mode|type=="string") and (.solo|type=="boolean") and (.repo_root|type=="string") and (.request_file|type=="string") and (.plan_under_review|type=="string") and (.claude_review|type=="string") and (.codex_review|type=="string") and (.final_review|type=="string") and (.plan_path|type=="string") and (.raw_input_file|type=="string")'

__cog_review_plan_multi_setup_usage() {
  cog::fn::ui_data "Usage: cog review-plan-multi-setup [--json] [--solo] [--output <absolute.md>] <plan-or-inline-input>"
}

# Consume only the leading flag tokens (--solo, --output, -- terminator) and keep the rest
# of the input verbatim (newlines preserved), so an inline plan pasted as the
# argument is not collapsed into a single whitespace-joined line.
__cog_review_plan_multi_setup_parse() {
  local raw="$1"
  local out_solo="$2" out_output="$3" out_input="$4"
  local parsed_solo=false parsed_output="" rest="$raw" value
  # strip leading whitespace
  rest="${rest#"${rest%%[![:space:]]*}"}"
  while true; do
    case "$rest" in
      --solo | --solo[[:space:]]*)
        parsed_solo=true
        rest="${rest#--solo}"
        rest="${rest#"${rest%%[![:space:]]*}"}"
        ;;
      --output | --output[[:space:]]*)
        [[ -z $parsed_output ]] || cog::fn::error_raise_with_exit 2 "InvalidInput" \
          "duplicate review-plan-multi output" "option: --output" "" "pass --output once"
        rest="${rest#--output}"
        rest="${rest#"${rest%%[![:space:]]*}"}"
        [[ -n $rest ]] || cog::fn::error_raise_with_exit 2 "MissingArgument" \
          "review-plan-multi output path is required" "option: --output" "" "pass an absolute .md path"
        value="${rest%%[[:space:]]*}"
        [[ $value == /* ]] || cog::fn::error_raise_with_exit 2 "InvalidInput" \
          "review-plan-multi output path must be absolute" "path: ${value}" "" "pass an absolute .md path"
        [[ $value == *.md ]] || cog::fn::error_raise_with_exit 2 "InvalidInput" \
          "review-plan-multi output must be markdown" "path: ${value}" "" "use a .md path"
        parsed_output="$value"
        rest="${rest#"$value"}"
        rest="${rest#"${rest%%[![:space:]]*}"}"
        ;;
      -- | --[[:space:]]*)
        rest="${rest#--}"
        rest="${rest#"${rest%%[![:space:]]*}"}"
        break
        ;;
      -*)
        cog::fn::error_raise_with_exit 2 "InvalidInput" \
          "unknown review-plan-multi flag" "option: ${rest%%[[:space:]]*}" "" \
          "expected --solo (prefix inline text starting with '-' with '--')"
        ;;
      *)
        break
        ;;
    esac
  done
  [[ -n $rest ]] || cog::fn::error_raise_with_exit 2 "MissingArgument" \
    "plan input is required" "usage: cog review-plan-multi-setup [--json] [--solo] [--output <absolute.md>] <input>" \
    "expected a plan file or inline plan+context text" ""
  printf -v "$out_solo" '%s' "$parsed_solo"
  printf -v "$out_output" '%s' "$parsed_output"
  printf -v "$out_input" '%s' "$rest"
}

# Input-form classification is shared with cog plan-gate so the setup surface and
# the plan gate can never disagree about what was passed. This surface accepts
# only the file and inline forms; a directory is rejected here rather than
# enumerated, so one review always reads exactly one plan.

__cog_review_plan_multi_setup_build_json() {
  local raw="$1"
  local solo output_override input mode abs classified run_dir repo_root
  local plan_path="" raw_input_file=""
  local request_file plan_under_review claude_review codex_review final_review

  __cog_review_plan_multi_setup_parse "$raw" solo output_override input
  classified="$(cog::fn::plan_gate::classify_input "$input")"
  mode="${classified%%$'\t'*}"
  abs="${classified#*$'\t'}"
  [[ $mode != dir ]] || cog::fn::error_raise_with_exit 2 "InvalidInput" \
    "review-plan-multi does not review a directory" "path: ${abs}" "" \
    "pass a single plan file or inline plan+context text"

  run_dir="$(cog::fn::rundir_create review-plan-multi)"
  repo_root="$(cog::fn::git_root)"
  request_file="${run_dir}/request.md"
  plan_under_review="${run_dir}/plan-under-review.md"
  claude_review="${run_dir}/claude-review.md"
  codex_review="${run_dir}/codex-review.md"
  final_review="${output_override:-${run_dir}/final-review.md}"

  case "$mode" in
    file)
      plan_path="$abs"
      ;;
    inline)
      raw_input_file="${run_dir}/raw-input.txt"
      printf '%s\n' "$input" >"$raw_input_file" \
        || cog::fn::error_raise "JsonWriteFailed" \
          "could not write raw input" "path: ${raw_input_file}" "" \
          "check run directory permissions"
      ;;
  esac

  jq -n \
    --arg run_dir "$run_dir" \
    --arg mode "$mode" \
    --argjson solo "$solo" \
    --arg repo_root "$repo_root" \
    --arg request_file "$request_file" \
    --arg plan_under_review "$plan_under_review" \
    --arg claude_review "$claude_review" \
    --arg codex_review "$codex_review" \
    --arg final_review "$final_review" \
    --arg plan_path "$plan_path" \
    --arg raw_input_file "$raw_input_file" \
    '{run_dir: $run_dir, mode: $mode, solo: $solo, repo_root: $repo_root,
      request_file: $request_file, plan_under_review: $plan_under_review,
      claude_review: $claude_review, codex_review: $codex_review,
      final_review: $final_review, plan_path: $plan_path,
      raw_input_file: $raw_input_file}'
}

cog::cmd::review_plan_multi_setup() {
  local mode=human raw="" json
  if [[ ${1:-} == --json ]]; then
    mode="json"
    shift
  fi
  case "${1:-}" in
    -h | --help)
      __cog_review_plan_multi_setup_usage
      return 0
      ;;
  esac
  raw="${1:-}"
  json="$(__cog_review_plan_multi_setup_build_json "$raw")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$__cog_review_plan_multi_setup_self_check" "$json"
  else
    cog::fn::ui_data "RUN_DIR=$(jq -r '.run_dir' <<<"$json")"
    cog::fn::ui_data "MODE=$(jq -r '.mode' <<<"$json")"
    cog::fn::ui_data "SOLO=$(jq -r 'if .solo then 1 else 0 end' <<<"$json")"
    cog::fn::ui_data "REPO_ROOT=$(jq -r '.repo_root' <<<"$json")"
    cog::fn::ui_data "REQUEST_FILE=$(jq -r '.request_file' <<<"$json")"
    cog::fn::ui_data "PLAN_UNDER_REVIEW=$(jq -r '.plan_under_review' <<<"$json")"
    cog::fn::ui_data "CLAUDE_REVIEW=$(jq -r '.claude_review' <<<"$json")"
    cog::fn::ui_data "CODEX_REVIEW=$(jq -r '.codex_review' <<<"$json")"
    cog::fn::ui_data "FINAL_REVIEW=$(jq -r '.final_review' <<<"$json")"
    cog::fn::ui_data "PLAN_PATH=$(jq -r '.plan_path' <<<"$json")"
    cog::fn::ui_data "RAW_INPUT_FILE=$(jq -r '.raw_input_file' <<<"$json")"
  fi
}
