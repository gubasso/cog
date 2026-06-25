# shellcheck shell=bash
: 'desc: Parse plan-multi arguments and create run state.'

__cog_plan_multi_setup_self_check='(.run_dir|type=="string") and (.solo|type=="boolean") and (.repo_root|type=="string") and (.orientation_file|type=="string") and (.output|type=="string") and (.research_root|type=="string") and (.brief_file|type=="string") and (.claude_plan|type=="string") and (.codex_plan|type=="string")'

__cog_plan_multi_setup_usage() {
  cog::fn::ui_data "Usage: cog plan-multi-setup [--json] [arguments-string]"
}

# Consume only the leading flag tokens (--solo, --output, --research-root, --
# terminator) and keep the remaining orientation verbatim (newlines and repeated
# whitespace preserved), so the original orientation is not collapsed into a
# single whitespace-joined line before it becomes the worker brief's verbatim base.
__cog_plan_multi_setup_parse() {
  local raw="$1"
  local out_solo="$2" out_output="$3" out_research_root="$4" out_orientation="$5"
  local parsed_solo=false parsed_output="" parsed_research_root="" rest="$raw" head value
  # strip leading whitespace
  rest="${rest#"${rest%%[![:space:]]*}"}"
  while true; do
    head="${rest%%[[:space:]]*}"
    case "$head" in
      --solo)
        parsed_solo=true
        rest="${rest#--solo}"
        rest="${rest#"${rest%%[![:space:]]*}"}"
        ;;
      --output=*)
        parsed_output="${head#--output=}"
        [[ -n $parsed_output ]] || cog::fn::error_raise_with_exit 2 "MissingArgument" \
          "missing output" "option: --output" "" "run 'cog plan-multi-setup --help'"
        rest="${rest#"$head"}"
        rest="${rest#"${rest%%[![:space:]]*}"}"
        ;;
      --output)
        rest="${rest#--output}"
        rest="${rest#"${rest%%[![:space:]]*}"}"
        value="${rest%%[[:space:]]*}"
        [[ -n $value && $value != --* ]] || cog::fn::error_raise_with_exit 2 "MissingArgument" \
          "missing output" "option: --output" "" "run 'cog plan-multi-setup --help'"
        parsed_output="$value"
        rest="${rest#"$value"}"
        rest="${rest#"${rest%%[![:space:]]*}"}"
        ;;
      --research-root=*)
        parsed_research_root="${head#--research-root=}"
        [[ -n $parsed_research_root ]] || cog::fn::error_raise_with_exit 2 "MissingArgument" \
          "missing research root" "option: --research-root" "" "run 'cog plan-multi-setup --help'"
        rest="${rest#"$head"}"
        rest="${rest#"${rest%%[![:space:]]*}"}"
        ;;
      --research-root)
        rest="${rest#--research-root}"
        rest="${rest#"${rest%%[![:space:]]*}"}"
        value="${rest%%[[:space:]]*}"
        [[ -n $value && $value != --* ]] || cog::fn::error_raise_with_exit 2 "MissingArgument" \
          "missing research root" "option: --research-root" "" "run 'cog plan-multi-setup --help'"
        parsed_research_root="$value"
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
          "unknown plan-multi flag" "option: $head" "" "expected --output, --research-root, or --solo"
        ;;
      *)
        break
        ;;
    esac
  done
  [[ -n $rest ]] || cog::fn::error_raise_with_exit 2 "MissingArgument" \
    "orientation is required" "usage: cog plan-multi-setup [--json] [arguments-string]" "" ""
  if [[ -n $parsed_output ]]; then
    cog::fn::plan_artifact::require_absolute_path "$parsed_output" output
  fi
  printf -v "$out_solo" '%s' "$parsed_solo"
  printf -v "$out_output" '%s' "$parsed_output"
  printf -v "$out_research_root" '%s' "$parsed_research_root"
  printf -v "$out_orientation" '%s' "$rest"
}

__cog_plan_multi_setup_build_json() {
  local raw="$1" solo output research_root orientation run_dir repo_root
  local orientation_file brief_file claude_plan codex_plan resolved_output
  __cog_plan_multi_setup_parse "$raw" solo output research_root orientation
  run_dir="$(cog::fn::rundir_create plan-multi)"
  repo_root="$(cog::fn::git_root)"
  orientation_file="${run_dir}/orientation.txt"
  printf '%s\n' "$orientation" >"$orientation_file" || cog::fn::error_raise "JsonWriteFailed" \
    "could not write orientation" "path: ${orientation_file}" "" "check run directory permissions"
  if [[ -n $output ]]; then
    resolved_output="$output"
  else
    resolved_output="${run_dir}/final-plan.md"
  fi
  brief_file="${run_dir}/plan-brief.md"
  claude_plan="${run_dir}/claude-plan.md"
  codex_plan="${run_dir}/codex-plan.md"

  jq -n \
    --arg run_dir "$run_dir" \
    --argjson solo "$solo" \
    --arg repo_root "$repo_root" \
    --arg orientation_file "$orientation_file" \
    --arg output "$resolved_output" \
    --arg research_root "$research_root" \
    --arg brief_file "$brief_file" \
    --arg claude_plan "$claude_plan" \
    --arg codex_plan "$codex_plan" \
    '{run_dir: $run_dir, solo: $solo, repo_root: $repo_root,
      orientation_file: $orientation_file, output: $output,
      research_root: $research_root, brief_file: $brief_file,
      claude_plan: $claude_plan, codex_plan: $codex_plan}'
}

cog::cmd::plan_multi_setup() {
  local mode=human raw="" json
  if [[ ${1:-} == --json ]]; then
    mode="json"
    shift
  fi
  case "${1:-}" in
    -h | --help)
      __cog_plan_multi_setup_usage
      return 0
      ;;
  esac
  raw="${1:-}"
  json="$(__cog_plan_multi_setup_build_json "$raw")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$__cog_plan_multi_setup_self_check" "$json"
  else
    cog::fn::ui_data "RUN_DIR=$(jq -r '.run_dir' <<<"$json")"
    cog::fn::ui_data "SOLO=$(jq -r 'if .solo then 1 else 0 end' <<<"$json")"
    cog::fn::ui_data "REPO_ROOT=$(jq -r '.repo_root' <<<"$json")"
    cog::fn::ui_data "ORIENTATION_FILE=$(jq -r '.orientation_file' <<<"$json")"
    cog::fn::ui_data "OUTPUT=$(jq -r '.output' <<<"$json")"
    cog::fn::ui_data "RESEARCH_ROOT=$(jq -r '.research_root' <<<"$json")"
    cog::fn::ui_data "BRIEF_FILE=$(jq -r '.brief_file' <<<"$json")"
    cog::fn::ui_data "CLAUDE_PLAN=$(jq -r '.claude_plan' <<<"$json")"
    cog::fn::ui_data "CODEX_PLAN=$(jq -r '.codex_plan' <<<"$json")"
  fi
}
