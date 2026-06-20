# shellcheck shell=bash

cog::fn::plan_review::template() {
  local input_plan_path="$1"
  local request_path="$2"
  local repo_root="$3"
  local research_json="$4"
  local generated research_root research_index research_exists

  generated="$(date -u +%Y-%m-%d)"
  research_root="$(jq -r '.root' <<<"$research_json")"
  research_index="$(jq -r '.index' <<<"$research_json")"
  research_exists="$(jq -r '.exists' <<<"$research_json")"
  cat <<EOF
# Annotated Plan Review

> Artifact: plan-review | Generated: ${generated} | Repo: ${repo_root}
> Input Plan: ${input_plan_path}
> Request: ${request_path}

## Verdict

APPROVED|MODIFIED

## Review Summary

## Research Shelf

- Root: \`${research_root}\`
- Index: \`${research_index}\`
- Exists: \`${research_exists}\`

## Annotated Plan

### APPROVED

### MODIFIED

### REMOVED

### ADDED

## Assumptions

## Risks
EOF
}

__cog_plan_review_error_json() {
  local reason="$1"
  jq -cn --arg reason "$reason" '{reason: $reason}'
}

cog::fn::plan_review::validate_content() {
  local path="${1:-}"
  local token ok=true
  local -a errors=()

  cog::fn::plan_artifact::file_nonempty "$path" "plan review"
  grep -q '^# Annotated Plan Review$' "$path" || {
    ok=false
    errors+=("$(__cog_plan_review_error_json "missing Annotated Plan Review H1")")
  }
  grep -q '^## Verdict$' "$path" || {
    ok=false
    errors+=("$(__cog_plan_review_error_json "missing Verdict section")")
  }
  for token in APPROVED MODIFIED REMOVED ADDED; do
    grep -q "$token" "$path" || {
      ok=false
      errors+=("$(__cog_plan_review_error_json "missing ${token} vocabulary")")
    }
  done

  jq -n \
    --argjson ok "$ok" \
    --arg path "$path" \
    --argjson errors "$(printf '%s\n' "${errors[@]}" | jq -s '.')" \
    '{ok: $ok, path: $path, errors: $errors}'
}

cog::fn::plan_review::save_json() {
  local input_plan_path="${1:-}"
  local request_path="${2:-}"
  local output_override="${3:-}"
  local repo_root="${4:-}"
  local research_root_override="${5:-}"
  local paths research_shelf content output_path

  cog::fn::plan_artifact::require_absolute_path "$input_plan_path" plan
  cog::fn::plan_artifact::require_absolute_path "$request_path" request
  cog::fn::plan_artifact::file_nonempty "$input_plan_path" plan
  cog::fn::plan_artifact::file_nonempty "$request_path" request
  [[ -z $output_override ]] || cog::fn::plan_artifact::require_absolute_path "$output_override" output
  [[ -n $repo_root ]] || repo_root="$(pwd -P)"

  paths="$(cog::fn::plan_artifact::resolve_paths_json "plan-review" "$(basename -- "$input_plan_path")" "$output_override" "$research_root_override")"
  research_shelf="$(jq -c '.research_shelf' <<<"$paths")"
  content="$(cog::fn::plan_review::template "$input_plan_path" "$request_path" "$repo_root" "$research_shelf")"
  output_path="$(jq -r '.output_path' <<<"$paths")"
  cog::fn::plan_artifact::write_file "$output_path" "$content"

  jq -n \
    --arg schema "cog.plan-review.v1" \
    --arg action "save" \
    --argjson ok true \
    --arg run_dir "$(jq -r '.run_dir' <<<"$paths")" \
    --arg input_plan_path "$input_plan_path" \
    --arg request_path "$request_path" \
    --arg output_path "$output_path" \
    --argjson research_shelf "$research_shelf" \
    '{schema: $schema, action: $action, ok: $ok, run_dir: $run_dir,
      input_plan_path: $input_plan_path, request_path: $request_path,
      output_path: $output_path, research_shelf: $research_shelf}'
}

cog::fn::plan_review::orchestrator_json() {
  local input_plan_path="${1:-}"
  local request_path="${2:-}"
  local output_path="${3:-}"
  local repo_root research_shelf content

  cog::fn::plan_artifact::require_absolute_path "$input_plan_path" plan
  cog::fn::plan_artifact::require_absolute_path "$request_path" request
  cog::fn::plan_artifact::require_absolute_path "$output_path" output
  cog::fn::plan_artifact::file_nonempty "$input_plan_path" plan
  cog::fn::plan_artifact::file_nonempty "$request_path" request
  repo_root="$(pwd -P)"
  research_shelf="$(cog::fn::plan_artifact::research_shelf_json)"
  content="$(cog::fn::plan_review::template "$input_plan_path" "$request_path" "$repo_root" "$research_shelf")"
  cog::fn::plan_artifact::write_file "$output_path" "$content"

  jq -n \
    --arg schema "cog.plan-review.v1" \
    --arg action "orchestrator" \
    --argjson ok true \
    --arg input_plan_path "$input_plan_path" \
    --arg request_path "$request_path" \
    --arg output_path "$output_path" \
    '{schema: $schema, action: $action, ok: $ok,
      input_plan_path: $input_plan_path, request_path: $request_path,
      output_path: $output_path}'
}

cog::fn::plan_review::validate_json() {
  local path="${1:-}"
  local report

  cog::fn::plan_artifact::require_absolute_path "$path" "plan-review"
  report="$(cog::fn::plan_review::validate_content "$path")"
  jq -n \
    --arg schema "cog.plan-review.v1" \
    --arg action "validate" \
    --argjson report "$report" \
    '{schema: $schema, action: $action, ok: $report.ok,
      path: $report.path, errors: $report.errors}'
}
