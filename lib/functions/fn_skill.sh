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

# Classify an authored or installed SKILL.md path into its source class.
# `codex` and `claude` are the runtime-native classes under skills-native/;
# `portable` is the single-owner class under skills/<name>/ that installs
# byte-identically into every supported agent root. Native patterns are matched
# first because a case glob's `*` also spans `/`, so the portable pattern would
# otherwise swallow the deeper native paths. An empty result means the path is
# not a governed skill source and callers skip class checks.
cog::fn::skill::runtime_for_path() {
  local file="$1"
  case "$file" in
    skills-native/codex/*/SKILL.md | */skills-native/codex/*/SKILL.md | .agents/skills/*/SKILL.md | */.agents/skills/*/SKILL.md) printf '%s\n' codex ;;
    skills-native/claude/*/SKILL.md | */skills-native/claude/*/SKILL.md | .claude/skills/*/SKILL.md | */.claude/skills/*/SKILL.md) printf '%s\n' claude ;;
    skills/*/SKILL.md | */skills/*/SKILL.md) printf '%s\n' portable ;;
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

cog::fn::skill::is_plan_reviewer_intent() {
  local file="$1"
  grep -qiE 'review implementation plans|review this plan|^# Plan Reviewer|^name:[[:space:]]*plan-reviewer|^name:[[:space:]]*review-plan' "$file"
}

cog::fn::skill::is_executor_intent() {
  local file="$1"
  grep -qE '^# Plan Review Execute' "$file" && return 0
  grep -qF 'Codex plans' "$file" && grep -qF 'Codex implements' "$file"
}

# Report the 1-based line numbers carrying an emoji.
#
# The (*UTF) verb is load-bearing, not decoration. Every code point in the class
# is above U+FFFF, and PCRE accepts those only in UTF mode, which grep enables
# from the locale. Under LC_ALL=C the pattern failed to compile, grep exited 2,
# and the old `|| true` swallowed it — so the gate reported a clean file for
# every skill and the lint failed open exactly where it was meant to bite. The
# verb turns UTF mode on inside the pattern, so the class compiles under every
# locale, and a status above 1 is now an error rather than "no match".
cog::fn::skill::emoji_lines_json() {
  local file="$1" emoji_lines status=0
  emoji_lines="$(grep -nP '(*UTF)[\x{1F300}-\x{1FAFF}\x{2600}-\x{27BF}\x{1F1E6}-\x{1F1FF}]' "$file")" || status=$?
  ((status <= 1)) || cog::fn::error_raise "InvalidInput" \
    "could not scan a skill for emoji" "path: ${file}" "grep exit status: ${status}" \
    "check that grep supports -P with UTF patterns"
  printf '%s\n' "$emoji_lines" | cut -d: -f1 | cog::fn::skill::json_number_array_from_lines
}

cog::fn::skill::untagged_fence_lines_json() {
  local file="$1" fence_lines
  fence_lines="$(awk '/^```/{if(!inf){inf=1; l=$0; sub(/^```[ \t]*/,"",l); if(l=="") print NR} else {inf=0}}' "$file" || true)"
  printf '%s\n' "$fence_lines" | cog::fn::skill::json_number_array_from_lines
}

cog::fn::skill::allowed_frontmatter_keys_json() {
  local runtime="$1"
  case "$runtime" in
    # A portable package installs the same bytes into every supported agent
    # root, so its frontmatter must be valid in all of them. The allowlist is
    # therefore the intersection of the runtime allowlists below, which is the
    # upstream Agent Skills required pair.
    portable | codex)
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
