# shellcheck shell=bash

# Deterministic "is this input a reviewable implementation plan?" gate for the
# review-plan-* family. Review judgment stays in the skills; cog owns the
# structural floor so every reviewer rejects a bare prompt the same way, with
# the same reason text, instead of re-deriving the check in prose.
#
# The floor composes two existing checks rather than inventing a third rubric:
# the strict plan-doc heading contract (cog::fn::plan_doc::validate_content) and
# the canonical plan-section signals (cog::fn::assess_input::*), so a plan that
# a non-cog producer wrote still clears the gate when it is genuinely a plan.

__cog_plan_gate_self_check='(.schema=="cog.plan-gate.v1") and (.action|type=="string") and (.ok|type=="boolean") and (.mode|type=="string") and (.verdict|type=="string") and (.sources|type=="array") and (.missing|type=="array")'

# Minimum distinct canonical sections a non-plan-doc source must carry.
COG_PLAN_GATE_MIN_SECTIONS=3

# Canonical sections that carry the plan's actual work. A source with headings
# but none of these is context, notes, or a status surface, not a plan.
cog::fn::plan_gate::body_sections() {
  printf '%s\n' \
    'implementation plan' plan approach \
    steps tasks phase phases round rounds
}

# Normalized, deduplicated heading titles: the leading `#`s and surrounding
# whitespace stripped, inner whitespace collapsed, lowercased. Two headings that
# differ only in case or spacing are one section, so "## PHASE" and "## Phase"
# cannot both count toward the floor.
cog::fn::plan_gate::normalized_headings() {
  local path="${1:-}"

  [[ -n $path ]] || cog::fn::error_raise "MissingArgument" \
    "missing plan gate source path" "function: cog::fn::plan_gate::normalized_headings" "" \
    "pass a file path"

  grep -iE '^#{1,6}[[:space:]]+' "$path" 2>/dev/null \
    | sed -E 's/^#{1,6}[[:space:]]+//; s/[[:space:]]+$//; s/[[:space:]]+/ /g' \
    | tr '[:upper:]' '[:lower:]' \
    | sort -u || true
}

# Canonical section labels one normalized heading title carries, matched on word
# boundaries. Substring matching counted "planning status" as the `plan` section
# and "background" as the `round` section, which let a status surface clear the
# section floor; a label must be a whole word (or whole phrase) in the title.
cog::fn::plan_gate::heading_labels() {
  local title="${1:-}" label

  while IFS= read -r label; do
    if [[ $title =~ (^|[^[:alnum:]])${label}([^[:alnum:]]|$) ]]; then
      printf '%s\n' "$label"
    fi
  done < <(cog::fn::assess_input::canonical_sections)
  return 0
}

# Every canonical label carried by any heading in the file, deduplicated. Unlike
# assess-input's `plan_headings`, this is boundary-matched, so it is safe to both
# count sections from and test for a plan-body section.
cog::fn::plan_gate::canonical_labels() {
  local path="${1:-}" title

  [[ -n $path ]] || cog::fn::error_raise "MissingArgument" \
    "missing plan gate source path" "function: cog::fn::plan_gate::canonical_labels" "" \
    "pass a file path"

  while IFS= read -r title; do
    [[ -n $title ]] || continue
    cog::fn::plan_gate::heading_labels "$title"
  done < <(cog::fn::plan_gate::normalized_headings "$path") | sort -u
  return 0
}

# Count the distinct headings that carry at least one canonical plan section
# label. assess-input's `heading_count` counts matched *labels*, and the
# canonical labels overlap ("phase" and "phases" both hit a single "## Phases"),
# so one heading can contribute several. The gate needs a count of real
# sections, or a two-heading status surface clears a three-section floor.
cog::fn::plan_gate::canonical_heading_count() {
  local path="${1:-}" title count=0

  [[ -n $path ]] || cog::fn::error_raise "MissingArgument" \
    "missing plan gate source path" "function: cog::fn::plan_gate::canonical_heading_count" "" \
    "pass a file path"

  while IFS= read -r title; do
    [[ -n $title ]] || continue
    if [[ -n $(cog::fn::plan_gate::heading_labels "$title") ]]; then
      count=$((count + 1))
    fi
  done < <(cog::fn::plan_gate::normalized_headings "$path")

  printf '%s\n' "$count"
}

cog::fn::plan_gate::self_check() {
  printf '%s\n' "$__cog_plan_gate_self_check"
}

# Classify the input form: an existing file, an existing directory, or inline
# text. Emits "MODE\tABS" where ABS is the resolved absolute path for file/dir
# modes and empty for inline mode. Shared with cog review-plan-multi-setup so
# both surfaces classify identically.
cog::fn::plan_gate::classify_input() {
  local input="${1:-}" abs

  if [[ -f $input ]]; then
    abs="$(realpath -- "$input")"
    printf 'file\t%s\n' "$abs"
  elif [[ -d $input ]]; then
    abs="$(realpath -- "$input")"
    printf 'dir\t%s\n' "$abs"
  else
    printf 'inline\t\n'
  fi
}

__cog_plan_gate_source_json() {
  local path="$1" ok="$2" strict="$3" headings_json="$4" reason="$5"
  shift 5
  local missing_json

  missing_json="$(cog::fn::skill::json_string_array "$@")"
  jq -cn \
    --arg path "$path" \
    --argjson ok "$ok" \
    --argjson strict "$strict" \
    --argjson plan_headings "$headings_json" \
    --argjson missing "$missing_json" \
    --arg reason "$reason" \
    '{path: $path, ok: $ok, plan_doc_shape: $strict, plan_headings: $plan_headings,
      missing: $missing, reason: $reason}'
}

# Verdict for one candidate plan file. Never raises on a bad candidate: an
# unreadable, empty, or thin file is a verdict, not a usage error.
cog::fn::plan_gate::source_verdict_json() {
  local path="${1:-}"
  local empty_headings headings_json heading_count body_hit=false
  local doc_json strict=false has_heading=false ok=false reason=""
  local -a missing=() labels=()

  [[ -n $path ]] || cog::fn::error_raise "MissingArgument" \
    "missing plan gate source path" "function: cog::fn::plan_gate::source_verdict_json" "" \
    "pass a file path"

  empty_headings="$(cog::fn::skill::json_string_array)"
  if [[ ! -f $path || ! -r $path ]]; then
    __cog_plan_gate_source_json "$path" false false "$empty_headings" \
      "not a readable file" "a readable markdown file"
    return 0
  fi
  if [[ ! -s $path ]]; then
    __cog_plan_gate_source_json "$path" false false "$empty_headings" \
      "file is empty" "plan content"
    return 0
  fi

  doc_json="$(cog::fn::plan_doc::validate_content "$path")"
  jq -e '.ok == true' <<<"$doc_json" >/dev/null && strict=true

  # Both the section count and the body-section test read the same
  # boundary-matched label set, so they can never disagree about what a heading
  # is. assess-input's substring `plan_headings` is not used for either.
  mapfile -t labels < <(cog::fn::plan_gate::canonical_labels "$path")
  headings_json="$(cog::fn::skill::json_string_array "${labels[@]}")"
  heading_count="$(cog::fn::plan_gate::canonical_heading_count "$path")"
  grep -qE '^#{1,6}[[:space:]]+' "$path" && has_heading=true
  while IFS= read -r section; do
    jq -e --arg s "$section" 'index($s)' <<<"$headings_json" >/dev/null 2>&1 && body_hit=true
  done < <(cog::fn::plan_gate::body_sections)

  if [[ $strict == true ]]; then
    ok=true
  elif [[ $has_heading == true && $heading_count -ge $COG_PLAN_GATE_MIN_SECTIONS && $body_hit == true ]]; then
    ok=true
  fi

  if [[ $ok == false ]]; then
    [[ $has_heading == true ]] || missing+=("a markdown heading")
    [[ $heading_count -ge $COG_PLAN_GATE_MIN_SECTIONS ]] \
      || missing+=("at least ${COG_PLAN_GATE_MIN_SECTIONS} canonical plan sections (found ${heading_count})")
    [[ $body_hit == true ]] \
      || missing+=("a plan-body section (implementation plan, approach, steps, tasks, phases, or rounds)")
    reason="not a reviewable plan: missing $(
      cog::fn::skill::json_string_array "${missing[@]}" | jq -r 'join("; ")'
    )"
  fi

  __cog_plan_gate_source_json "$path" "$ok" "$strict" "$headings_json" "$reason" "${missing[@]}"
}

__cog_plan_gate_dir_sources() {
  local dir="$1"

  find "$dir" -maxdepth 1 -type f -name '*.md' | sort
}

# Aggregate verdict across every candidate source. A directory passes when at
# least one markdown source in it is a plan; the rest are supporting notes.
cog::fn::plan_gate::check_json() {
  local mode="${1:-}" target="${2:-}"
  local sources_json='[]' verdicts_json='[]' source verdict
  local ok=false verdict_label reason="" passing_json matched_json missing_json

  [[ -n $mode ]] || cog::fn::error_raise "MissingArgument" \
    "missing plan gate mode" "function: cog::fn::plan_gate::check_json" "" \
    "pass file, dir, or inline"
  [[ -n $target ]] || cog::fn::error_raise "MissingArgument" \
    "missing plan gate target" "function: cog::fn::plan_gate::check_json" "" \
    "pass a path"

  case "$mode" in
    file | inline)
      sources_json="$(jq -cn --arg p "$target" '[$p]')"
      ;;
    dir)
      while IFS= read -r source; do
        [[ -n $source ]] || continue
        sources_json="$(jq -c --arg p "$source" '. + [$p]' <<<"$sources_json")"
      done < <(__cog_plan_gate_dir_sources "$target")
      ;;
    *)
      cog::fn::error_raise "InvalidInput" \
        "unknown plan gate mode" "mode: ${mode}" "" "pass file, dir, or inline"
      ;;
  esac

  while IFS= read -r source; do
    [[ -n $source ]] || continue
    verdict="$(cog::fn::plan_gate::source_verdict_json "$source")"
    verdicts_json="$(jq -c --argjson v "$verdict" '. + [$v]' <<<"$verdicts_json")"
  done < <(jq -r '.[]' <<<"$sources_json")

  jq -e 'any(.[]; .ok)' <<<"$verdicts_json" >/dev/null 2>&1 && ok=true
  passing_json="$(jq -c '[.[] | select(.ok) | .path]' <<<"$verdicts_json")"
  matched_json="$(jq -c '[.[] | select(.ok) | .plan_headings[]] | unique' <<<"$verdicts_json")"
  if [[ $ok == true ]]; then
    verdict_label="plan"
    missing_json='[]'
  else
    verdict_label="insufficient"
    missing_json="$(jq -c '[.[].missing[]] | unique' <<<"$verdicts_json")"
    if [[ $mode == dir ]] && jq -e 'length == 0' <<<"$sources_json" >/dev/null; then
      reason="not a reviewable plan: the directory contains no markdown sources"
      missing_json="$(cog::fn::skill::json_string_array "at least one markdown plan file")"
    else
      reason="$(jq -r '[.[] | select(.ok | not) | .reason] | first // "not a reviewable plan"' <<<"$verdicts_json")"
    fi
  fi

  jq -n \
    --arg schema "cog.plan-gate.v1" \
    --arg action "check" \
    --argjson ok "$ok" \
    --arg mode "$mode" \
    --arg verdict "$verdict_label" \
    --argjson sources "$sources_json" \
    --argjson passing_sources "$passing_json" \
    --argjson matched_sections "$matched_json" \
    --argjson missing "$missing_json" \
    --argjson source_verdicts "$verdicts_json" \
    --arg reason "$reason" \
    '{schema: $schema, action: $action, ok: $ok, mode: $mode, verdict: $verdict,
      sources: $sources, passing_sources: $passing_sources,
      matched_sections: $matched_sections, missing: $missing,
      source_verdicts: $source_verdicts, reason: $reason}'
}
