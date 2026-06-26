# shellcheck shell=bash

# Single source of truth for the context-brief section contract. scaffold, build,
# and validate all read this one ordered key list and the heading/guidance maps so
# the three verbs cannot drift apart.
#
# Sections are delimited by collision-proof HTML-comment anchors
# (<!-- cog:context-brief:section=<key> -->) rather than markdown headings, because
# the Original Request section carries the user's prompt as-is and that content may
# itself contain markdown headings. Anchors keep section boundaries unambiguous.
#
# `original-request` is mechanically injected from a rawfile by build (cheap
# insurance that the raw ask is always present); the remaining sections are authored
# by the coordinator. The brief is the best-constructed input: an oriented summary
# plus the full substance and artifacts that bear on the task, with the coordinator's
# own verdict omitted for bias isolation.

__cog_context_brief_keys=(
  original-request
  objective
  output-format
  boundaries
  context-decisions
  artifacts
  effort-guidance
  not-evaluated
)

# The one section build injects verbatim from --request; everything else is authored.
__cog_context_brief_injected_key=original-request

cog::fn::context_brief_keys() {
  printf '%s\n' "${__cog_context_brief_keys[@]}"
}

__cog_context_brief_heading() {
  case "$1" in
    original-request) printf 'Original Request' ;;
    objective) printf 'Objective' ;;
    output-format) printf 'Output Format' ;;
    boundaries) printf 'Boundaries / Scope' ;;
    context-decisions) printf 'Context & Decisions' ;;
    artifacts) printf 'Artifacts & Pointers' ;;
    effort-guidance) printf 'Effort Guidance' ;;
    not-evaluated) printf 'Not Evaluated' ;;
    *) return 1 ;;
  esac
}

__cog_context_brief_guidance() {
  case "$1" in
    objective) printf 'A well-oriented statement of the goal, crafted from the whole session, not just the last message.' ;;
    output-format) printf 'The exact result/output contract the worker must produce.' ;;
    boundaries) printf 'What is in and out of scope; what not to re-litigate.' ;;
    context-decisions) printf 'Substantive background: decisions and rationale, research, and findings. Summarize narrative for clarity; carry the full substance that bears on the work.' ;;
    artifacts) printf 'Generated plans, documents, and code excerpts inline when load-bearing; absolute-path pointers for large or external artifacts.' ;;
    effort-guidance) printf 'How much depth and effort the worker should spend.' ;;
    not-evaluated) printf 'Explicitly list fields or areas deliberately skipped or not yet evaluated; when none, say so.' ;;
    *) return 1 ;;
  esac
}

__cog_context_brief_anchor() {
  printf '<!-- cog:context-brief:section=%s -->' "$1"
}

# Emit the author-filled body skeleton: every section except the injected
# original-request. Each section carries its anchor, human heading, and a one-line
# guidance comment the author replaces.
cog::fn::context_brief_scaffold() {
  local key heading guidance first=true
  for key in "${__cog_context_brief_keys[@]}"; do
    [[ $key == "$__cog_context_brief_injected_key" ]] && continue
    heading="$(__cog_context_brief_heading "$key")"
    guidance="$(__cog_context_brief_guidance "$key")"
    [[ $first == true ]] || printf '\n'
    first=false
    printf '%s\n' "$(__cog_context_brief_anchor "$key")"
    printf '## %s\n\n' "$heading"
    printf '<!-- %s -->\n' "$guidance"
  done
}

# Print the body lines of one section: everything between that section's anchor and
# the next section anchor (or EOF). Used by the non-empty validator.
__cog_context_brief_section_body() {
  local file="$1" key="$2"
  awk -v start="$(__cog_context_brief_anchor "$key")" '
    $0 == start { capture = 1; next }
    capture && /^<!-- cog:context-brief:section=/ { capture = 0 }
    capture { print }
  ' "$file"
}

# A section is "filled" when, after removing its heading line and any HTML comments
# (scaffold guidance), real non-whitespace content remains.
__cog_context_brief_section_filled() {
  local file="$1" key="$2" body stripped
  body="$(__cog_context_brief_section_body "$file" "$key")"
  stripped="$(printf '%s\n' "$body" \
    | sed -e 's/<!--.*-->//g' -e '/^[[:space:]]*#\{1,2\}[[:space:]]/d')"
  [[ -n ${stripped//[[:space:]]/} ]]
}

# Fail closed unless the brief exists, is readable, non-empty, carries the canonical
# title, and every required section is present (anchor) and filled (non-empty body).
cog::fn::context_brief_assert() {
  local brief="$1" key heading
  [[ -f $brief && -r $brief ]] || cog::fn::error_raise "InputUnreadable" \
    "context brief is missing or unreadable" "path: ${brief}" "" \
    "run 'cog context-brief build' to generate it"
  [[ -s $brief ]] || cog::fn::error_raise "InvalidInput" \
    "context brief is empty" "path: ${brief}" "" \
    "build a non-empty context brief"
  grep -qxF '# Context Brief' "$brief" || cog::fn::error_raise "InvalidInput" \
    "context brief is missing its title" "path: ${brief}" \
    "expected a '# Context Brief' heading" "regenerate via 'cog context-brief build'"

  for key in "${__cog_context_brief_keys[@]}"; do
    heading="$(__cog_context_brief_heading "$key")"
    grep -qxF "$(__cog_context_brief_anchor "$key")" "$brief" || cog::fn::error_raise "InvalidInput" \
      "context brief is missing a required section" "path: ${brief}" \
      "expected the '${heading}' section (${key})" \
      "include every section from the context-brief contract and regenerate"
    __cog_context_brief_section_filled "$brief" "$key" || cog::fn::error_raise "InvalidInput" \
      "context brief section is empty" "path: ${brief}" \
      "section '${heading}' (${key}) has no content" \
      "fill the '${heading}' section and regenerate"
  done
}

# Assemble a brief by injecting the raw request verbatim under its anchor, then
# appending the coordinator-authored body. The request is copied byte-for-byte from
# the rawfile so the raw ask is always attached, never paraphrased away.
cog::fn::context_brief_build() {
  local request_file="$1" body_file="$2" out="$3"

  {
    printf '# Context Brief\n\n'
    printf '%s\n' "$(__cog_context_brief_anchor "$__cog_context_brief_injected_key")"
    printf '## %s\n\n' "$(__cog_context_brief_heading "$__cog_context_brief_injected_key")"
    cat "$request_file"
    printf '\n\n'
    cat "$body_file"
    printf '\n'
  } >"$out" || cog::fn::error_raise "JsonWriteFailed" \
    "could not write context brief" "path: ${out}" "" "check the output path and retry"

  cog::fn::context_brief_assert "$out"
}
