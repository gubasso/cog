# shellcheck shell=bash

cog::fn::plan_doc::template() {
  local title="$1"
  local repo_root="$2"
  local research_json="$3"
  local generated research_root research_index research_exists

  generated="$(date -u +%Y-%m-%d)"
  research_root="$(jq -r '.root' <<<"$research_json")"
  research_index="$(jq -r '.index' <<<"$research_json")"
  research_exists="$(jq -r '.exists' <<<"$research_json")"
  cat <<EOF
# ${title}

> Artifact: plan-doc | Generated: ${generated} | Repo: ${repo_root}

## Goal

## Context

## Research Shelf

- Root: \`${research_root}\`
- Index: \`${research_index}\`
- Exists: \`${research_exists}\`

## Implementation Plan

1.

## Acceptance Criteria

- [ ]

## Assumptions

## Risks
EOF
}

__cog_plan_doc_error_json() {
  local reason="$1"
  jq -cn --arg reason "$reason" '{reason: $reason}'
}

cog::fn::plan_doc::validate_text() {
  local content="${1:-}"
  local label="${2:-<text>}"
  local ok=true
  local -a errors=()

  [[ -n $content ]] || cog::fn::error_raise "InvalidInput" \
    "plan doc is empty" "source: ${label}" "" "provide a non-empty plan document"
  grep -q '^# ' <<<"$content" || {
    ok=false
    errors+=("$(__cog_plan_doc_error_json "missing H1 heading")")
  }
  grep -q '^## Goal$' <<<"$content" || {
    ok=false
    errors+=("$(__cog_plan_doc_error_json "missing Goal section")")
  }
  grep -q '^## Implementation Plan$' <<<"$content" || {
    ok=false
    errors+=("$(__cog_plan_doc_error_json "missing Implementation Plan section")")
  }
  grep -q '^## Acceptance Criteria$' <<<"$content" || {
    ok=false
    errors+=("$(__cog_plan_doc_error_json "missing Acceptance Criteria section")")
  }

  jq -n \
    --argjson ok "$ok" \
    --arg path "$label" \
    --argjson errors "$(printf '%s\n' "${errors[@]}" | jq -s '.')" \
    '{ok: $ok, path: $path, errors: $errors}'
}

cog::fn::plan_doc::validate_content() {
  local path="${1:-}"

  cog::fn::plan_artifact::file_nonempty "$path" "plan doc"
  cog::fn::plan_doc::validate_text "$(<"$path")" "$path"
}

cog::fn::plan_doc::require_valid_file() {
  local path="${1:-}" report
  report="$(cog::fn::plan_doc::validate_content "$path")"
  jq -e '.ok == true' <<<"$report" >/dev/null || cog::fn::error_raise "InvalidInput" \
    "plan document failed validation" "path: ${path}" "$(jq -c '.errors' <<<"$report")" \
    "provide a structurally valid plan-doc"
}

cog::fn::plan_doc::require_valid_text() {
  local content="${1:-}" label="${2:-<text>}" report
  report="$(cog::fn::plan_doc::validate_text "$content" "$label")"
  jq -e '.ok == true' <<<"$report" >/dev/null || cog::fn::error_raise "InvalidInput" \
    "plan document failed validation" "source: ${label}" "$(jq -c '.errors' <<<"$report")" \
    "provide a structurally valid plan-doc"
}

cog::fn::plan_doc::save_json() {
  local title="${1:-}"
  local repo_root="${2:-}"
  local output_override="${3:-}"
  local research_root_override="${4:-}"
  local paths research_shelf content output_path

  [[ -n $title ]] || cog::fn::error_raise "MissingArgument" \
    "missing plan-doc title" "option: --title" "" "run 'cog plan-doc --help'"
  [[ -n $repo_root ]] || repo_root="$(pwd -P)"
  paths="$(cog::fn::plan_artifact::resolve_paths_json "plan-doc" "$title" "$output_override" "$research_root_override")"
  research_shelf="$(jq -c '.research_shelf' <<<"$paths")"
  content="$(cog::fn::plan_doc::template "$title" "$repo_root" "$research_shelf")"
  output_path="$(jq -r '.output_path' <<<"$paths")"
  cog::fn::plan_artifact::write_file "$output_path" "$content"

  jq -n \
    --arg schema "cog.plan-doc.v1" \
    --arg action "save" \
    --argjson ok true \
    --arg run_dir "$(jq -r '.run_dir' <<<"$paths")" \
    --arg output_path "$output_path" \
    --arg slug "$(jq -r '.slug' <<<"$paths")" \
    --argjson research_shelf "$research_shelf" \
    '{schema: $schema, action: $action, ok: $ok, run_dir: $run_dir,
      output_path: $output_path, slug: $slug, research_shelf: $research_shelf}'
}

cog::fn::plan_doc::validate_json() {
  local path="${1:-}"
  local report

  cog::fn::plan_artifact::require_absolute_path "$path" "plan-doc"
  report="$(cog::fn::plan_doc::validate_content "$path")"
  jq -n \
    --arg schema "cog.plan-doc.v1" \
    --arg action "validate" \
    --argjson report "$report" \
    '{schema: $schema, action: $action, ok: $report.ok,
      path: $report.path, errors: $report.errors}'
}
