# shellcheck shell=bash

# Registry for the unified `cog gate` noun. A "gate" is a canonical,
# marker-delimited stanza stamped into a SKILL.md file and drift-checked by
# `cog skill-lint`. This file does NOT own the stanza wording: the single source
# of truth for each gate's text stays in fn_skill.sh (cog::fn::skill::*_gate_*).
# The registry only maps a stable gate id to those primitives so `cog gate` and
# the linter share one renderer and can never drift (ADR-0045).

# Stable, ordered gate ids. Used by `cog gate list` and id validation.
__cog_gate_ids=(
  plan-mode
  context-brief
)

cog::fn::gate::ids() {
  printf '%s\n' "${__cog_gate_ids[@]}"
}

cog::fn::gate::is_id() {
  local id="$1" known
  for known in "${__cog_gate_ids[@]}"; do
    [[ $id == "$known" ]] && return 0
  done
  return 1
}

cog::fn::gate::description() {
  case "$1" in
    plan-mode)
      printf 'Phase 0 plan-mode gate for executor/runner orchestrators (Claude only).'
      ;;
    context-brief)
      printf 'Fresh-context-boundary gate: build a validated context brief before dispatch.'
      ;;
    *) return 1 ;;
  esac
}

# Emit the full stamped block (marker + canonical stanza) for one gate id and
# skill name. Byte-for-byte identical to the retired `cog plan-mode-gate render`
# and `cog context-brief gate render` output.
cog::fn::gate::render() {
  local id="$1" name="$2"
  case "$id" in
    plan-mode) cog::fn::skill::plan_mode_gate_render "$name" ;;
    context-brief) cog::fn::skill::context_brief_gate_render "$name" ;;
    *) return 1 ;;
  esac
}

# Extract the inlined stanza that follows a gate's marker in a skill file.
cog::fn::gate::extract() {
  local id="$1" file="$2"
  case "$id" in
    plan-mode) cog::fn::skill::plan_mode_gate_extract "$file" ;;
    context-brief) cog::fn::skill::context_brief_gate_extract "$file" ;;
    *) return 1 ;;
  esac
}

# The expected canonical paragraph (sans marker) for one gate id and skill name.
cog::fn::gate::paragraph() {
  local id="$1" name="$2"
  case "$id" in
    plan-mode) cog::fn::skill::plan_mode_gate_paragraph "$name" ;;
    context-brief) cog::fn::skill::context_brief_gate_paragraph "$name" ;;
    *) return 1 ;;
  esac
}

# Whitespace-normalize a stanza for wrapping-independent comparison. One shared
# normalizer for every gate id.
cog::fn::gate::normalize() {
  cog::fn::skill::plan_mode_gate_normalize "$1"
}

# The marker-line regex for a gate id, used to locate the stamped region.
cog::fn::gate::marker_regex() {
  case "$1" in
    plan-mode) printf '%s' '<!--[[:space:]]*cog-plan-mode-gate[[:space:]]*-->' ;;
    context-brief) printf '%s' '<!--[[:space:]]*cog-context-brief-gate[[:space:]]*-->' ;;
    *) return 1 ;;
  esac
}

# Stamp the canonical block for one gate id into a file: replace the existing
# marker + stanza region in place, or append a fresh block at EOF when the marker
# is absent. Idempotent — re-stamping an up-to-date file leaves it byte-identical.
# Prints "STAMPED <path>" on success. Deterministic mechanics live here, not in
# skill prose.
cog::fn::gate::stamp() {
  local id="$1" name="$2" file="$3"
  local marker block tmp
  marker="$(cog::fn::gate::marker_regex "$id")" || return 1
  block="$(cog::fn::gate::render "$id" "$name")" || return 1

  tmp="$(mktemp)" || return 1
  if grep -qE "$marker" "$file"; then
    # Replace the marker line and its following stanza (skip blanks, then the
    # consecutive non-blank paragraph lines up to the next blank/EOF).
    awk -v marker="$marker" -v block="$block" '
      replacing {
        if (!started) { if ($0 ~ /^[[:space:]]*$/) next; started = 1; next }
        if ($0 ~ /^[[:space:]]*$/) { replacing = 0; print; next }
        next
      }
      $0 ~ marker { print block; replacing = 1; started = 0; next }
      { print }
    ' "$file" >"$tmp" || {
      rm -f "$tmp"
      return 1
    }
  else
    {
      cat "$file"
      printf '\n%s\n' "$block"
    } >"$tmp" || {
      rm -f "$tmp"
      return 1
    }
  fi

  cat "$tmp" >"$file" || {
    rm -f "$tmp"
    return 1
  }
  rm -f "$tmp"
  printf 'STAMPED %s\n' "$file"
}
