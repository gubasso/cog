# shellcheck shell=bash
# Deterministic mechanics for the bootstrap template-refresh review routine
# (ADR-0062): freshness selection over the research shelf plus template-SoT
# origin/writability surfacing. Judgment — which hooks, what to change, how to
# merge — stays in the bootstrap worker prose; this file owns the freshness,
# record, and resolution mechanics the six workers share so no freshness
# composition logic is duplicated across their SKILL.md bodies.

cog::fn::bootstrap_review::valid_domain() {
  case "${1:-}" in
    precommit | editorconfig | nix | repo | ci | taskrunner) return 0 ;;
    *) return 1 ;;
  esac
}

# Template tree name(s) under skill-refs/templates/ for a domain. Most domains map
# 1:1; precommit uses the `pre-commit` tree; repo spans gitignore, license, and
# readme (gitignore carries the typed freshness key, the other two are reported
# template roots).
cog::fn::bootstrap_review::template_domains() {
  case "${1:-}" in
    precommit) printf '%s\n' "pre-commit" ;;
    editorconfig) printf '%s\n' "editorconfig" ;;
    nix) printf '%s\n' "nix" ;;
    repo) printf '%s\n' "gitignore license readme" ;;
    ci) printf '%s\n' "ci" ;;
    taskrunner) printf '%s\n' "taskrunner" ;;
    *) return 1 ;;
  esac
}

# Default freshness window (days). Chosen at record time as the revalidate-after
# offset, so `check` only compares dates.
cog::fn::bootstrap_review::default_freshness_days() { printf '14\n'; }

# The freshness cache key: keyed by domain AND detected type so a Rust review does
# not suppress a Python one.
cog::fn::bootstrap_review::topic_tags_json() {
  local domain="${1:-}" type="${2:-}"
  jq -cn --arg d "$domain" --arg t "$type" '["bootstrap-template", $d, $t]'
}

# Resolve the research shelf root without requiring the directory to exist yet, so
# a `check` against a project that never stamped still resolves to a (missing)
# index rather than an empty path. Order matches cog::fn::research::root minus the
# existence gate.
cog::fn::bootstrap_review::research_root() {
  local override="${1:-}" data_root
  if [[ -n $override ]]; then
    printf '%s\n' "$override"
    return 0
  fi
  if [[ -n ${COG_RESEARCH_SHELF_ROOT:-} ]]; then
    printf '%s\n' "$COG_RESEARCH_SHELF_ROOT"
    return 0
  fi
  data_root="$(cog::fn::data_root)" || return 1
  printf '%s/research-shelf\n' "$data_root"
}

# Reported template roots for a domain: one {domain, path, exists} object per
# template tree the domain owns.
cog::fn::bootstrap_review::template_roots_json() {
  local domain="${1:-}" tree path exists
  local -a trees=() objs=()
  read -r -a trees <<<"$(cog::fn::bootstrap_review::template_domains "$domain")"
  for tree in "${trees[@]}"; do
    if path="$(cog::fn::template::root "$tree" 2>/dev/null)"; then
      exists=false
      [[ -d $path ]] && exists=true
      objs+=("$(jq -cn --arg d "$tree" --arg p "$path" --argjson e "$exists" \
        '{domain: $d, path: $p, exists: $e}')")
    else
      objs+=("$(jq -cn --arg d "$tree" '{domain: $d, path: null, exists: false}')")
    fi
  done
  printf '%s\n' "${objs[@]}" | jq -cs '.'
}

# Check the freshness state of a domain/type template review. Selects fresh entries
# via the shared cog::fn::research::fresh_entries helper (tag-subset + date), and
# distinguishes stale (a matching entry exists but is past revalidate-after) from
# missing (no matching entry) from invalid (skill-refs unresolved). Freshness is
# decided purely against the stamped revalidate-after, so this only compares dates;
# the window is chosen at stamp time. Args: <domain> <type> [research-root].
cog::fn::bootstrap_review::check_json() {
  local domain="${1:-}" type="${2:-}" research_override="${3:-}"
  local research_root index tags_json as_of skill_refs template_roots
  local all_matching fresh_matching

  cog::fn::research::require_jq
  as_of="$(date -u +%F)"
  tags_json="$(cog::fn::bootstrap_review::topic_tags_json "$domain" "$type")"
  skill_refs="$(cog::fn::skill_refs_origin_json)"
  template_roots="$(cog::fn::bootstrap_review::template_roots_json "$domain")"

  research_root="$(cog::fn::bootstrap_review::research_root "$research_override")" || research_root=""
  index=""
  [[ -n $research_root ]] && index="${research_root}/index.jsonl"

  if [[ -n $index && -f $index ]]; then
    all_matching="$(jq -R -s -c --argjson tags "$tags_json" '
      [ split("\n")[] | select(length > 0) | (fromjson? // empty) ]
      | map(select((."topic-tags" // []) as $t | (($tags - $t) | length) == 0))
    ' "$index")"
    fresh_matching="$(cog::fn::research::fresh_entries "$index" "$tags_json" "$as_of")"
  else
    all_matching='[]'
    fresh_matching='[]'
  fi

  jq -n \
    --arg schema "cog.bootstrap-template-review.v1" \
    --arg domain "$domain" --arg type "$type" \
    --argjson tags "$tags_json" --arg as_of "$as_of" \
    --argjson skill_refs "$skill_refs" \
    --argjson template_roots "$template_roots" \
    --argjson all "$all_matching" \
    --argjson fresh "$fresh_matching" '
    ($skill_refs.origin) as $origin
    | ($fresh | sort_by(."recorded-date") | last) as $freshest
    | ($all | sort_by(."recorded-date") | last) as $newest
    | (if $origin == "none" then {state: "invalid", fresh: false, pick: null}
       elif ($fresh | length) > 0 then {state: "fresh", fresh: true, pick: $freshest}
       elif ($all | length) > 0 then {state: "stale", fresh: false, pick: $newest}
       else {state: "missing", fresh: false, pick: null} end) as $r
    | {schema: $schema, ok: ($origin != "none"), action: "check",
       domain: $domain, type: $type, topic_tags: $tags, as_of: $as_of,
       review: {state: $r.state, fresh: $r.fresh},
       last_recorded_date: ($r.pick."recorded-date" // null),
       revalidate_after: ($r.pick."revalidate-after" // null),
       entry_id: ($r.pick.id // null),
       summary: ($r.pick."stable-summary" // null),
       skill_refs: {root: $skill_refs.root, origin: $skill_refs.origin, writable: $skill_refs.writable},
       template_roots: $template_roots}'
}

# Record a dated template review for a domain/type and report it with the template
# SoT origin and any changed template paths. Fails fast when the skill-refs template
# tree is unresolved or not writable — the dual-write-to-SoT contract cannot be
# honored there, and surfacing that is preferable to a silent divergence. Args:
# <domain> <type> <summary> <sources-json-array> <changed-json-array>
# [research-root] [freshness-days].
cog::fn::bootstrap_review::stamp_json() {
  local domain="${1:-}" type="${2:-}" summary="${3:-}" sources_json="${4:-[]}" changed_json="${5:-[]}"
  local research_override="${6:-}" freshness_days="${7:-}"
  local skill_refs origin writable root today revalidate_after tags_json skills_json
  local entry_without_id entry_id entry_json research_root record_json index

  cog::fn::research::require_jq
  [[ -n $freshness_days ]] || freshness_days="$(cog::fn::bootstrap_review::default_freshness_days)"

  skill_refs="$(cog::fn::skill_refs_origin_json)"
  origin="$(jq -r '.origin' <<<"$skill_refs")"
  writable="$(jq -r '.writable' <<<"$skill_refs")"
  root="$(jq -r '.root // ""' <<<"$skill_refs")"

  [[ $origin != none ]] || cog::fn::error_raise "InputNotFound" \
    "bootstrap template SoT is unresolved" \
    "origin: none" "no skill-refs root under XDG or the repo checkout" \
    "deploy skill-refs or run from the cog repo before stamping a review"
  [[ $writable == true ]] || cog::fn::error_raise "InvalidInput" \
    "bootstrap template SoT is not writable" \
    "origin: ${origin}, root: ${root}" \
    "the dual-write to skill-refs/templates cannot be honored on a read-only tree" \
    "make the resolved skill-refs template root writable (fix install permissions) or run against a repo checkout"

  today="$(date -u +%F)"
  revalidate_after="$(date -u -d "+${freshness_days} days" +%F 2>/dev/null)" \
    || revalidate_after="$(date -u -v "+${freshness_days}d" +%F 2>/dev/null)"
  cog::fn::research::date_valid "$revalidate_after" || cog::fn::error_raise "InvalidInput" \
    "could not compute revalidate-after date" "freshness-days: ${freshness_days}" \
    "date arithmetic failed" "install GNU coreutils date or pass a valid --freshness-days"

  tags_json="$(cog::fn::bootstrap_review::topic_tags_json "$domain" "$type")"
  skills_json="$(jq -cn --arg s "bootstrap-${domain}" '[$s]')"
  entry_without_id="$(jq -n -cS \
    --arg recorded_date "$today" \
    --arg stable_summary "$summary" \
    --arg revalidate_after "$revalidate_after" \
    --argjson topic_tags "$tags_json" \
    --argjson sources "$sources_json" \
    --argjson consuming_skills "$skills_json" \
    '{"recorded-date": $recorded_date, "topic-tags": $topic_tags, sources: $sources,
      "stable-summary": $stable_summary, "revalidate-after": $revalidate_after,
      "consuming-skills": $consuming_skills}')"
  entry_id="$(cog::fn::research::entry_generate_id "$entry_without_id")"
  entry_json="$(jq -cS --arg id "$entry_id" '. + {id: $id}' <<<"$entry_without_id")"

  research_root="$(cog::fn::bootstrap_review::research_root "$research_override")" \
    || cog::fn::error_raise "InputNotFound" "research shelf root unresolved" \
      "function: cog::fn::bootstrap_review::stamp_json" "" "deploy cog data or run from the repo"
  record_json="$(cog::fn::research::record_json "$research_root" "$entry_json")"
  index="$(jq -r '.index' <<<"$record_json")"

  jq -n \
    --arg schema "cog.bootstrap-template-review.v1" \
    --arg domain "$domain" --arg type "$type" \
    --argjson freshness_days "$freshness_days" \
    --arg revalidate_after "$revalidate_after" \
    --arg recorded_date "$today" \
    --argjson entry "$entry_json" \
    --arg entry_id "$entry_id" \
    --arg index "$index" \
    --argjson changed "$changed_json" \
    --argjson skill_refs "$skill_refs" '
    {schema: $schema, ok: true, action: "stamp", domain: $domain, type: $type,
     freshness_days: $freshness_days, recorded_date: $recorded_date,
     revalidate_after: $revalidate_after, entry_id: $entry_id, entry: $entry,
     index: $index, changed_templates: $changed,
     skill_refs: {root: $skill_refs.root, origin: $skill_refs.origin, writable: $skill_refs.writable}}'
}
