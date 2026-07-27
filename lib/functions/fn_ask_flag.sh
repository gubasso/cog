# shellcheck shell=bash

# Runtime renderer for the `ask` skill's research-flag instruction paragraphs.
# The canonical wording lives in data/ask-flags/instructions.yaml (top-level
# `ask_flags` map); this module loads it and prints one flag's paragraph so both
# the Claude and Codex `ask` twins can inject identical text at runtime without
# stamping it into the skill body. The data file is the single flag registry: the
# valid ids are exactly its `ask_flags` keys, so there is no second list to drift.

# Load the merged ask-flags table as JSON. Dies (via data helpers) when the table
# is missing or unparseable.
cog::fn::ask_flag::_table() {
  local dir
  dir="$(cog::fn::data::path ask-flags)" || cog::fn::error_raise "InputNotFound" \
    "ask-flags data table not found" "path: ask-flags" "" \
    "reinstall cog to restore the ask-flags data table under the cog data root"
  cog::fn::data::load_dir "$dir"
}

# Emit the flag ids (sorted) one per line.
cog::fn::ask_flag::ids() {
  cog::fn::ask_flag::_table | jq -r '.ask_flags | keys[]'
}

# True when the given id is a known ask flag.
cog::fn::ask_flag::is_id() {
  local id="$1" known
  while IFS= read -r known; do
    [[ $id == "$known" ]] && return 0
  done < <(cog::fn::ask_flag::ids)
  return 1
}

# Emit a one-line summary for `list`: the first sentence of the paragraph.
cog::fn::ask_flag::description() {
  local id="$1"
  cog::fn::ask_flag::_table \
    | jq -r --arg f "$id" '.ask_flags[$f] // empty' \
    | tr '\n' ' ' \
    | sed -E 's/^[[:space:]]+//; s/([.]).*$/\1/; s/[[:space:]]+$//'
}

# Print one flag's canonical instruction paragraph to stdout.
cog::fn::ask_flag::render() {
  local id="$1" text
  text="$(cog::fn::ask_flag::_table | jq -r --arg f "$id" '.ask_flags[$f] // empty')"
  [[ -n $text ]] || return 1
  printf '%s\n' "$text"
}
