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

cog::fn::skill::has_plan_mode_gate() {
  local file="$1"
  grep -qE '<!--[[:space:]]*cog-plan-mode-gate[[:space:]]*-->' "$file"
}

# True when a skill must carry the plan-mode gate. The gate lives on the
# executor-*/runner-* orchestrator layer: those callers gate once at entry, then
# delegate to gate-free plan/review workers. See ADR-0037.
cog::fn::skill::requires_plan_mode_gate() {
  local name="$1"
  case "$(cog::fn::skill::classify_prefix "$name")" in
    executor | runner) return 0 ;;
    *) return 1 ;;
  esac
}

# Single source of truth for the plan-mode gate stanza. Detection of plan mode
# stays probabilistic in skill prose (ADR-0015); this helper owns the canonical
# text so cog plan-mode-gate render, cog skill-lint, and cog-skill-creator never
# drift.
cog::fn::skill::plan_mode_gate_paragraph() {
  local name="$1"
  cog::fn::skill::name_is_valid "$name" || return 2
  printf '%s\n' '**Phase 0 — Plan-mode gate.** If Claude Code **plan mode** is active (a system-reminder says plan'
  printf '%s\n' 'mode is on / that you must not make edits), **STOP** before any other work — parsing args,'
  printf '%s\n' 'researching, interviewing, delegating, or writing. Tell the user in one line to exit plan mode'
  # shellcheck disable=SC2016  # backticks here are literal Markdown, not command substitution
  printf '(`Shift+Tab`) and re-invoke `/%s`. Do not call `ExitPlanMode`, and do not silently continue.\n' "$name"
}

cog::fn::skill::plan_mode_gate_render() {
  local name="$1"
  printf '%s\n\n' '<!-- cog-plan-mode-gate -->'
  cog::fn::skill::plan_mode_gate_paragraph "$name" || return 2
}

# Extract the inlined gate paragraph: the consecutive non-blank lines that follow
# the gate marker (blank lines between marker and paragraph are skipped).
cog::fn::skill::plan_mode_gate_extract() {
  local file="$1"
  awk '
    !found && /<!--[[:space:]]*cog-plan-mode-gate[[:space:]]*-->/ {
      found = 1
      next
    }
    found && !started {
      if ($0 ~ /^[[:space:]]*$/) next
      started = 1
      print
      next
    }
    found && started {
      if ($0 ~ /^[[:space:]]*$/) exit
      print
    }
  ' "$file"
}

# Collapse every whitespace run (including newlines) to a single space and trim,
# so wording is compared independent of line wrapping.
cog::fn::skill::plan_mode_gate_normalize() {
  printf '%s' "$1" | LC_ALL=C tr '[:space:]' ' ' | LC_ALL=C tr -s ' ' | sed -e 's/^ *//' -e 's/ *$//'
}

cog::fn::skill::classify_prefix() {
  local name="$1"
  case "$name" in
    review-plan-*) printf '%s\n' review-plan ;;
    plan-*) printf '%s\n' plan ;;
    review-*) printf '%s\n' review ;;
    executor-*) printf '%s\n' executor ;;
    runner-*) printf '%s\n' runner ;;
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
  cog::fn::skill::is_plan_emitter "$file" || return 1
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
