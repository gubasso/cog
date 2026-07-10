# ADR-0083: Language-conditional knowledge-base spell checker (English→typos, non-English→cspell)

## Context and Problem Statement

The markdown/KB pre-commit template hardwired `crate-ci/typos` and shipped a `_typos.toml`. `typos`
is English-only by design — no non-English dictionary, no per-file language switch — so it flags valid
Portuguese words (e.g. `gere`) as misspellings, blocking multilingual knowledge bases. `typos` remains
the better checker for source code and English prose (fast, low-noise, zero false positives on unknown
words), so a blanket swap to `cspell` was wrong.

## Considered Options

- Block-swap: apply-template string-replaces the typos hook inside the ~200-line config.
- A second full `markdown-cspell` template directory.
- A `_spell/<variant>/` overlay plus a `--spell` flag and a deterministic language→variant mapper.

## Decision Outcome

Chosen option: **the `_spell/` overlay + `--spell` flag**. The base `markdown` config carries no spell
hook; `cog precommit-apply-template --type markdown --spell <typos|cspell>` copies the variant's
companions and appends its hook stanza (order-independent for pre-commit). `cog precommit-spell-select
--languages <csv>` maps a declared content-language set to the variant (any non-`en` locale → cspell;
otherwise typos). English-only KBs stay on `typos` (default, byte-equivalent to prior behavior); KBs
with non-English content get `cspell` with an English default and per-file
`<!-- cspell:dictionaries pt-br -->`. The seven code templates keep their inline `typos` untouched.
Block-swap was rejected as fragile against routine template edits; a duplicate directory was rejected
for duplicating the shared config and inviting drift. The "which languages" judgment stays in
`bootstrap-knowledge-base` prose; the deterministic mapping and overlay copy/append live in cog
(ADR-0008).

## Consequences

- Good: one shared markdown config, no duplication; both checkers first-class; per-file language
  selection for multilingual KBs. All assets ship in-repo under `skill-refs/templates/pre-commit/`
  (ADR-0071).
- Good: `cspell` is delivered via its hosted pre-commit hook under pre-commit's own managed Node — no
  devShell or system Node change.
- Bad: a new `_spell/` overlay convention that the template-refresh routine must respect.

## Status

Implemented — `lib/commands/cmd_precommit_apply_template.sh`,
`lib/commands/cmd_precommit_spell_select.sh`, `skill-refs/templates/pre-commit/_spell/`,
`skill-refs/templates/pre-commit/markdown/.pre-commit-config.yaml`,
`skills/claude/bootstrap-precommit/SKILL.md`, and
`skills/claude/bootstrap-knowledge-base/SKILL.md`. Builds on ADR-0081 (KB bootstrap domain) and
ADR-0008 (skill/script boundary).
