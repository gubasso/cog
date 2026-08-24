# shellcheck shell=bash

cog::fn::skill::json_string_array() {
  if [[ $# -eq 0 ]]; then jq -cn '[]'; else printf '%s\n' "$@" | jq -R . | jq -s .; fi
}

cog::fn::skill::json_number_array_from_lines() {
  jq -R 'select(length > 0) | tonumber' | jq -s 'unique'
}

cog::fn::skill::name_normalize_frontmatter_value() {
  local name="$1"
  name="${name%\"}"
  name="${name#\"}"
  name="${name%\'}"
  name="${name#\'}"
  name="${name%"${name##*[![:space:]]}"}"
  name="${name#"${name%%[![:space:]]*}"}"
  printf '%s\n' "$name"
}

cog::fn::skill::name_is_valid() {
  local name="$1"
  [[ $name =~ ^[a-z0-9-]{1,64}$ ]] || return 1
  [[ $name != anthropic && $name != claude ]]
}

cog::fn::skill::parent_dir_name() {
  local file="$1" dir
  dir="$(dirname -- "$file")"
  basename -- "$dir"
}

cog::fn::skill::runtime_for_path() {
  local file="$1"
  case "$file" in
    skills/codex/*/SKILL.md | */skills/codex/*/SKILL.md) printf '%s\n' codex ;;
    skills/claude/*/SKILL.md | */skills/claude/*/SKILL.md | .claude/skills/*/SKILL.md | */.claude/skills/*/SKILL.md) printf '%s\n' claude ;;
    *) printf '%s\n' "" ;;
  esac
}

cog::fn::skill::line_count() {
  local file="$1" count
  count="$(wc -l <"$file")"
  printf '%s\n' "${count//[^0-9]/}"
}

cog::fn::skill::frontmatter_name() {
  local file="$1" name
  name="$(awk 'NR==1 && $0=="---"{f=1; next} f && $0=="---"{exit} f && /^name:[[:space:]]/{sub(/^name:[[:space:]]*/,""); print; exit}' "$file")"
  cog::fn::skill::name_normalize_frontmatter_value "$name"
}

cog::fn::skill::frontmatter_keys_json() {
  local file="$1"
  awk '
    NR == 1 && $0 == "---" { frontmatter = 1; next }
    frontmatter && $0 == "---" { exit }
    frontmatter && /^[A-Za-z0-9_-]+:[[:space:]]*/ {
      key = $0
      sub(/:.*/, "", key)
      print key
    }
  ' "$file" | LC_ALL=C sort -u | jq -R . | jq -s .
}

cog::fn::skill::has_frontmatter() {
  local file="$1"
  [[ $(sed -n '1p' "$file") == "---" ]] || return 1
  awk 'NR > 1 && $0 == "---" { found = 1; exit } END { exit found ? 0 : 1 }' "$file"
}

cog::fn::skill::has_trigger_tests() {
  local file="$1"
  grep -qE '<!--[[:space:]]*trigger-tests:' "$file"
}

cog::fn::skill::is_plan_emitter() {
  local file="$1"
  grep -qE '<!--[[:space:]]*cog-skill:[[:space:]]*plan-emitter[[:space:]]*-->' "$file"
}

cog::fn::skill::has_input_fidelity_marker() {
  local file="$1"
  grep -qE '<!--[[:space:]]*cog-skill:[[:space:]]*input-fidelity[[:space:]]*-->' "$file"
}

cog::fn::skill::classify_prefix() {
  local name="$1"
  case "$name" in
    review-plan-*) printf '%s\n' review-plan ;;
    plan-*) printf '%s\n' plan ;;
    review-*) printf '%s\n' review ;;
    executor-*) printf '%s\n' executor ;;
    bootstrap-*) printf '%s\n' bootstrap ;;
    *) printf '%s\n' other ;;
  esac
}

cog::fn::skill::name_in_namespace() {
  local namespace="$1" name="$2"
  cog::fn::skill::name_is_valid "$name" || return 1
  [[ "$(cog::fn::skill::classify_prefix "$name")" == "$namespace" ]]
}

cog::fn::skill::is_plan_reviewer_intent() {
  local file="$1"
  grep -qiE 'review implementation plans|review this plan|^# Plan Reviewer|^name:[[:space:]]*plan-reviewer|^name:[[:space:]]*review-plan' "$file"
}

cog::fn::skill::is_executor_intent() {
  local file="$1"
  grep -qE '^# Plan Review Execute' "$file" && return 0
  grep -qF 'Codex plans' "$file" && grep -qF 'Codex implements' "$file"
}

cog::fn::skill::emoji_lines_json() {
  local file="$1" emoji_lines
  emoji_lines="$(grep -nP '[\x{1F300}-\x{1FAFF}\x{2600}-\x{27BF}\x{1F1E6}-\x{1F1FF}]' "$file" | cut -d: -f1 || true)"
  printf '%s\n' "$emoji_lines" | cog::fn::skill::json_number_array_from_lines
}

cog::fn::skill::untagged_fence_lines_json() {
  local file="$1" fence_lines
  fence_lines="$(awk '/^```/{if(!inf){inf=1; l=$0; sub(/^```[ \t]*/,"",l); if(l=="") print NR} else {inf=0}}' "$file" || true)"
  printf '%s\n' "$fence_lines" | cog::fn::skill::json_number_array_from_lines
}

cog::fn::skill::draft_json() {
  local file="$1" name line_count under_500 valid_name has_trigger_tests ok reason="" emojis_json fences_json
  [[ -r $file && -f $file ]] || cog::fn::error_raise "InputUnreadable" "draft skill file is not readable" "path: ${file}" "" "check the path"
  line_count="$(cog::fn::skill::line_count "$file")"
  if [[ $line_count -le 500 ]]; then under_500=true; else under_500=false; fi
  name="$(cog::fn::skill::frontmatter_name "$file")"
  if cog::fn::skill::name_is_valid "$name"; then valid_name=true; else valid_name=false; fi
  if cog::fn::skill::has_trigger_tests "$file"; then has_trigger_tests=true; else has_trigger_tests=false; fi
  emojis_json="$(cog::fn::skill::emoji_lines_json "$file")"
  fences_json="$(cog::fn::skill::untagged_fence_lines_json "$file")"
  ok=true
  [[ $under_500 == true ]] || {
    ok=false
    reason="SKILL.md exceeds 500 lines"
  }
  [[ $valid_name == true ]] || {
    ok=false
    reason="${reason:-invalid or missing skill name}"
  }
  [[ $has_trigger_tests == true ]] || {
    ok=false
    reason="${reason:-missing trigger-tests comment}"
  }
  [[ $emojis_json == "[]" ]] || {
    ok=false
    reason="${reason:-emoji characters present}"
  }
  [[ $fences_json == "[]" ]] || {
    ok=false
    reason="${reason:-untagged code fences}"
  }
  jq -n --argjson ok "$ok" --arg file "$file" --argjson line_count "$line_count" --argjson under_500 "$under_500" \
    --arg name "$name" --argjson valid_name "$valid_name" --argjson has_trigger_tests "$has_trigger_tests" \
    --argjson emojis "$emojis_json" --argjson untagged_fences "$fences_json" --arg reason "$reason" \
    '{ok: $ok, mode: "draft", file: $file, line_count: $line_count, under_500: $under_500,
      name: $name, valid_name: $valid_name, has_trigger_tests: $has_trigger_tests,
      emojis: $emojis, untagged_fences: $untagged_fences, reason: (if $ok then null else $reason end)}'
}

cog::fn::skill::allowed_frontmatter_keys_json() {
  local runtime="$1"
  case "$runtime" in
    codex)
      cog::fn::skill::json_string_array name description
      ;;
    claude)
      cog::fn::skill::json_string_array \
        name description model effort argument-hint allowed-tools disable-model-invocation \
        user-invocable disallowed-tools when_to_use arguments context agent paths shell hooks \
        metadata license
      ;;
    *)
      cog::fn::skill::json_string_array
      ;;
  esac
}

# Suppression names must stay synchronized with docs/reference/skill-contract.md
# and test/integration/cmd_skill_lint.bats.
cog::fn::skill::allowed_lint_suppressions_json() {
  cog::fn::skill::json_string_array allow-inline-shell allow-orchestration-history
}

cog::fn::skill::unknown_frontmatter_keys_json() {
  local file="$1" runtime="$2" keys allowed
  keys="$(cog::fn::skill::frontmatter_keys_json "$file")"
  allowed="$(cog::fn::skill::allowed_frontmatter_keys_json "$runtime")"
  jq -cn --argjson keys "$keys" --argjson allowed "$allowed" '$keys - $allowed'
}

# Read a single frontmatter scalar value by key (empty when the key is absent).
cog::fn::skill::frontmatter_value() {
  local file="$1" key="$2" value
  value="$(awk -v key="$key" '
    NR==1 && $0=="---"{f=1; next}
    f && $0=="---"{exit}
    f && index($0, key ":")==1 {
      sub("^" key ":[[:space:]]*", "")
      print
      exit
    }' "$file")"
  cog::fn::skill::name_normalize_frontmatter_value "$value"
}

# Path to the Claude model/effort policy data (the governed-tier registry SoT).
cog::fn::skill::tier_data_path() {
  local override="${COG_MODEL_EFFORT_CLAUDE:-}"
  if [[ -n $override ]]; then
    printf '%s\n' "$override"
    return 0
  fi
  cog::fn::data::path "model-effort/claude"
}

cog::fn::skill::tier_data_json() {
  local path="${1:-}"
  [[ -n $path ]] || path="$(cog::fn::skill::tier_data_path)"
  [[ -e $path ]] || cog::fn::error_raise "InputNotFound" \
    "model/effort policy data not found" "path: ${path}" "" \
    "check data/model-effort/claude"
  cog::fn::data::load_dir "$path"
}

# Tier a skill name is explicitly pinned to in the registry, or empty if unlisted.
cog::fn::skill::registry_tier() {
  local name="$1" json
  json="$(cog::fn::skill::tier_data_json)"
  jq -r --arg name "$name" '
    [ .tiers | to_entries[] | select((.value.skills // []) | index($name)) | .key ] | first // empty
  ' <<<"$json"
}

# Prefix-default tier for a governed skill name, or empty for ungoverned prefixes.
cog::fn::skill::prefix_default_tier() {
  case "$1" in
    # A '-codex' launcher delegates the whole substantive turn to Codex and keeps
    # only argument handling, gating, dispatch, and reporting, so it rides LOW
    # regardless of what its base prefix would otherwise demand.
    *-codex) printf '%s\n' low ;;
    review-plan-*) printf '%s\n' high ;;
    review-oneshot*) printf '%s\n' xhigh ;;
    plan-*) printf '%s\n' high ;;
    executor-*) printf '%s\n' medium ;;
    bootstrap-*) printf '%s\n' low ;;
    *) printf '%s\n' "" ;;
  esac
}

# Expected tier for a skill name: explicit registry membership wins, else the
# prefix default, else "exempt" (ungoverned). Returns xhigh|high|medium|low|cheap|exempt.
cog::fn::skill::expected_tier() {
  local name="$1" rung
  rung="$(cog::fn::skill::registry_tier "$name")"
  [[ -n $rung ]] || rung="$(cog::fn::skill::prefix_default_tier "$name")"
  printf '%s\n' "${rung:-exempt}"
}

# Why a skill has its expected tier: registry | prefix-default | exempt.
cog::fn::skill::expected_tier_source() {
  local name="$1"
  if [[ -n $(cog::fn::skill::registry_tier "$name") ]]; then
    printf '%s\n' registry
  elif [[ -n $(cog::fn::skill::prefix_default_tier "$name") ]]; then
    printf '%s\n' prefix-default
  else
    printf '%s\n' exempt
  fi
}

# Resolve a skill's frontmatter (model, effort) to a tier name, or "unknown".
# Absent model and effort means "ride the session default" → high.
cog::fn::skill::tier_for_frontmatter() {
  local model="$1" effort="$2" json rung
  if [[ -z $model && -z $effort ]]; then
    printf '%s\n' high
    return 0
  fi
  if [[ $model == haiku && -z $effort ]]; then
    printf '%s\n' cheap
    return 0
  fi
  json="$(cog::fn::skill::tier_data_json)"
  # Explicitly pinning the session-default cell (e.g. opus+high) is equivalent to riding HIGH.
  rung="$(jq -r --arg model "$model" --arg effort "$effort" '
    ( [ .tiers | to_entries[] | select(.value.model == $model and .value.effort == $effort) | .key ] | first )
    // (if (.session_default.model == $model and .session_default.effort == $effort) then "high" else empty end)
    // empty
  ' <<<"$json")"
  printf '%s\n' "${rung:-unknown}"
}
