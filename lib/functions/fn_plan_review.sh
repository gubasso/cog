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

  # The errors array reaches jq as input, not as an --argjson argv string:
  # --argjson puts the value in argv, where one string above MAX_ARG_STRLEN
  # (128KiB on Linux) fails execve with E2BIG. An empty array makes printf emit
  # one blank line, which `jq -s` reads as zero inputs and slurps to [].
  printf '%s\n' "${errors[@]}" | jq -s \
    --argjson ok "$ok" \
    --arg path "$path" \
    '{ok: $ok, path: $path, errors: .}'
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

cog::fn::plan_review::items_json() {
  local path="${1:-}"
  local items

  cog::fn::plan_artifact::require_absolute_path "$path" "plan-review"
  cog::fn::plan_artifact::file_nonempty "$path" "plan review"

  items="$({
    awk '
      function escape(value, out) {
        out = value
        gsub(/\\/, "\\\\", out)
        gsub(/"/, "\\\"", out)
        gsub(/\t/, "\\t", out)
        gsub(/\r/, "\\r", out)
        gsub(/\n/, "\\n", out)
        return out
      }
      function trim_end(value) {
        sub(/[[:space:]]+$/, "", value)
        return value
      }
      function emit(annotation, start, finish, markdown, prefix, ordinal) {
        markdown = trim_end(markdown)
        if (markdown == "") return
        ordinal = ++counts[annotation]
        prefix = annotation == "APPROVED" ? "A" : (annotation == "MODIFIED" ? "M" : (annotation == "REMOVED" ? "R" : "D"))
        printf "{\"id\":\"%s%d\",\"annotation\":\"%s\",\"ordinal\":%d,\"start_line\":%d,\"end_line\":%d,\"markdown\":\"%s\"}\n", prefix, ordinal, annotation, ordinal, start, finish, escape(markdown)
      }
      function flush_section(   i, has_list, has_heading, start, finish, body, line, match_len) {
        if (section == "" || section_count == 0) { section_count = 0; return }
        has_list = has_heading = 0
        for (i = 1; i <= section_count; i++) {
          if (section_lines[i] ~ /^([-+*]|[0-9]+[.)])[[:space:]]+/) has_list = 1
          if (section_lines[i] ~ /^####[[:space:]]+/) has_heading = 1
        }
        if (has_list) {
          start = 0; body = ""; finish = 0
          for (i = 1; i <= section_count; i++) {
            line = section_lines[i]
            if (line ~ /^([-+*]|[0-9]+[.)])[[:space:]]+/) {
              if (start) emit(section, start, finish, body)
              start = section_numbers[i]
              match(line, /^([-+*]|[0-9]+[.)])[[:space:]]+/)
              body = substr(line, RLENGTH + 1)
              finish = section_numbers[i]
            } else if (start) {
              body = body "\n" line
              if (line !~ /^[[:space:]]*$/) finish = section_numbers[i]
            }
          }
          if (start) emit(section, start, finish, body)
        } else if (has_heading) {
          start = 0; body = ""; finish = 0
          for (i = 1; i <= section_count; i++) {
            line = section_lines[i]
            if (line ~ /^####[[:space:]]+/) {
              if (start) emit(section, start, finish, body)
              start = section_numbers[i]
              sub(/^####[[:space:]]+/, "", line)
              body = line
              finish = section_numbers[i]
            } else if (start) {
              body = body "\n" line
              if (line !~ /^[[:space:]]*$/) finish = section_numbers[i]
            }
          }
          if (start) emit(section, start, finish, body)
        } else {
          start = 0; body = ""; finish = 0
          for (i = 1; i <= section_count; i++) {
            line = section_lines[i]
            if (line ~ /^[[:space:]]*$/) {
              if (start) { emit(section, start, finish, body); start = 0; body = "" }
            } else {
              if (!start) start = section_numbers[i]
              body = body (body == "" ? "" : "\n") line
              finish = section_numbers[i]
            }
          }
          if (start) emit(section, start, finish, body)
        }
        delete section_lines
        delete section_numbers
        section_count = 0
      }
      /^## Annotated Plan$/ { in_annotated = 1; next }
      in_annotated && (/^# / || /^## /) { flush_section(); in_annotated = 0; section = ""; next }
      in_annotated && /^### (APPROVED|MODIFIED|REMOVED|ADDED)$/ {
        flush_section()
        section = substr($0, 5)
        next
      }
      in_annotated && /^### / { flush_section(); section = ""; next }
      in_annotated && section != "" {
        section_lines[++section_count] = $0
        section_numbers[section_count] = NR
      }
      END { flush_section() }
    ' "$path"
  } | jq -s '.')"

  jq -n \
    --arg schema "cog.plan-review.items.v1" \
    --arg action "items" \
    --arg path "$path" \
    --argjson items "$items" \
    '{schema: $schema, action: $action, ok: true, path: $path,
      count: ($items | length), items: $items}'
}

cog::fn::plan_review::fold_check_json() {
  local review="${1:-}" plan="${2:-}" manifest="${3:-}"
  local items manifest_json review_sha plan_sha manifest_sha report

  cog::fn::plan_artifact::require_absolute_path "$review" review
  cog::fn::plan_artifact::require_absolute_path "$plan" plan
  cog::fn::plan_artifact::require_absolute_path "$manifest" manifest
  cog::fn::plan_artifact::file_nonempty "$review" review
  cog::fn::plan_artifact::file_nonempty "$plan" plan
  cog::fn::plan_artifact::file_nonempty "$manifest" manifest

  items="$(cog::fn::plan_review::items_json "$review")"
  # Accept exactly one top-level JSON value. A syntax error or a multi-document
  # stream becomes `null` so the invalid_manifest branch reports it structurally
  # instead of failing --argjson before the report is built.
  if ! manifest_json="$(jq -cs 'if length == 1 then .[0] else null end' "$manifest" 2>/dev/null)"; then
    manifest_json=null
  fi
  [[ -n $manifest_json ]] || manifest_json=null
  review_sha="$(sha256sum "$review" | awk '{print $1}')"
  plan_sha="$(sha256sum "$plan" | awk '{print $1}')"
  manifest_sha="$(sha256sum "$manifest" | awk '{print $1}')"

  report="$(jq -n \
    --argjson extracted "$items" \
    --argjson manifest "$manifest_json" '
      def error($code; $message; $id): {code: $code, message: $message} + (if $id == null then {} else {id: $id} end);
      ($extracted.items | map(.id)) as $expected |
      (if ($manifest | type) != "object" then
        [error("invalid_manifest"; "manifest must be a JSON object"; null)]
      elif ($manifest.schema != "cog.plan-review.fold-manifest.v1") then
        [error("invalid_schema"; "manifest schema must be cog.plan-review.fold-manifest.v1"; null)]
      elif (($manifest | keys_unsorted) - ["schema", "dispositions"] | length) > 0 then
        [error("invalid_manifest"; "manifest contains unknown top-level fields"; null)]
      elif ($manifest.dispositions | type) != "array" then
        [error("invalid_manifest"; "manifest dispositions must be an array"; null)]
      else
        ($manifest.dispositions // []) as $ds |
        ($ds | map(select(type == "object"))) as $objects |
        ([range(0; $ds|length) as $i |
          ($ds[$i]) as $d |
          if ($d|type) != "object" then error("invalid_disposition"; "disposition must be an object"; null)
          elif (($d|keys_unsorted) - ["id", "disposition", "reason", "note"] | length) > 0 then error("invalid_disposition"; "disposition contains unknown fields"; ($d.id // null))
          elif (($d.id|type) != "string" or ($d.id|length) == 0) then error("invalid_id"; "disposition id must be a non-empty string"; null)
          elif ($d.disposition != "folded" and $d.disposition != "waived") then error("invalid_disposition"; "disposition must be folded or waived"; $d.id)
          elif ($d.disposition == "waived" and (($d.reason|type) != "string" or ($d.reason|gsub("\\s"; "")|length) == 0)) then error("blank_waiver_reason"; "waived disposition requires a non-blank reason"; $d.id)
          else empty end] +
          [$objects | group_by(.id)[] | select(length > 1) | error("duplicate_id"; "manifest id appears more than once"; .[0].id)] +
          [$objects[] | select((.id as $id | $expected | index($id)) == null) | error("unknown_id"; "manifest id is not present in the review"; .id)] +
          [$expected[] as $id | select(($objects | map(.id) | index($id)) == null) | error("missing_id"; "review item has no disposition"; $id)])
      end) as $errors |
      {ok: ($errors|length == 0), errors: $errors,
        total: ($expected|length),
        folded: (if (($manifest | if type == "object" then .dispositions else null end)|type) == "array" then [$manifest.dispositions[] | select(type == "object" and .disposition == "folded")]|length else 0 end),
        waived: (if (($manifest | if type == "object" then .dispositions else null end)|type) == "array" then [$manifest.dispositions[] | select(type == "object" and .disposition == "waived")]|length else 0 end)}
    ')"

  jq -n \
    --arg schema "cog.plan-review.fold-check.v1" \
    --arg action "fold-check" \
    --arg review_path "$review" \
    --arg plan_path "$plan" \
    --arg manifest_path "$manifest" \
    --arg review_sha256 "$review_sha" \
    --arg plan_sha256 "$plan_sha" \
    --arg manifest_sha256 "$manifest_sha" \
    --argjson report "$report" \
    '{schema: $schema, action: $action, ok: $report.ok,
      review_path: $review_path, plan_path: $plan_path, manifest_path: $manifest_path,
      review_sha256: $review_sha256, plan_sha256: $plan_sha256,
      manifest_sha256: $manifest_sha256,
      counts: {total: $report.total, folded: $report.folded, waived: $report.waived},
      errors: $report.errors}'
}
