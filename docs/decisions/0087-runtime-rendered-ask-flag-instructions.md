# ADR-0087: Runtime-Rendered `ask` Flag Instructions

> **Amended by [ADR-0088](0088-primary-source-verification-shared-reference.md).** The `web-search`
> directive graduated out of `data/ask-flags` into the shared
> `skill-refs/research/primary-source-verification.md`; `cog ask-flag` now serves only `real-world`.
> The runtime-render mechanism for `-r/real-world` is unchanged.

## Context and Problem Statement

The `ask` skill's research flags (`-w/--web-search`, and the new `-r/--real-world`) each carry a
verbose instruction paragraph. Inlining that prose in both the Claude and Codex twins bloats the
always-loaded skill body (the text loads on every run, even when the flag is not used) and duplicates
wording across two files that can drift. We want one source of truth whose text enters context only
when a flag actually fires.

## Considered Options

- Inline the paragraphs in both `SKILL.md` twins (status quo, duplicated).
- Stamp the paragraphs into both twins like the `cog gate` markers, pinned by a `skill-lint` rule.
- Store the paragraphs in a `cog` data table and render them at runtime via a new command; both twins
  call the same command to inject the text.

## Decision Outcome

Chosen option: **runtime render** — `data/ask-flags/instructions.yaml` holds the canonical paragraphs
(top-level `ask_flags` map, one entry per flag key), and `cog ask-flag render --flag <key>` prints
one paragraph to stdout. Both twins render-and-inject at runtime. The data file is the single flag
registry: valid ids are exactly its keys. Unlike `cog gate` (whose text must be visible in the file
for humans/lint), this text is injected into a delegated sub-prompt, so it need not live in the skill.

## Consequences

- Good: always-loaded skill body stays lean; the paragraph enters context only when its flag fires.
- Good: zero twin duplication and zero drift by construction — both twins call one command, so no
  drift-check lint rule is required.
- Good: rewording a flag instruction is a one-line data edit, no skill or code change.
- Bad: the paragraph is not visible in `SKILL.md`; readers follow the `cog ask-flag render` call.
- Bad: a new `data/` table adds explicit install wiring (clear + copy) that must not be forgotten.

## Status

Implemented. `lib/commands/cmd_ask_flag.sh` + `lib/functions/fn_ask_flag.sh` render from
`data/ask-flags/instructions.yaml`; `skills/claude/ask/SKILL.md` and `skills/codex/ask/SKILL.md`
inject at runtime. Follows the registry philosophy of ADR-0045 and the lean-positive prose of
ADR-0019.
