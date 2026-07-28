# ADR-0090: Markdown pre-commit layer (universal overlay)

## Context and Problem Statement

Markdown formatting and validation were knowledge-base-only: the dprint no-wrap rule (`markdown.textWrap: "never"`) and the markdownlint/relative-link gates lived only in the `markdown` pre-commit template, reachable via `--type markdown`. Every code project formats only JSON via dprint and excludes `.md` from `editorconfig-checker`, so their READMEs and `docs/*.md` were neither formatted nor linted.

## Considered Options

- Inline the markdown hooks into each per-type config (duplication and drift across nine templates).
- A shared `_markdown/` overlay appended to every deployed config, mirroring the `_nix/` and `_spell/` overlays.
- Leave markdown KB-only, so code repos' docs stay ungoverned.

## Decision Outcome

Chosen: **a universal `_markdown/` overlay applied to every type except `markdown`**.

- `skill-refs/templates/pre-commit/_markdown/` holds `hook.pre-commit.yaml` (dprint unwrap + relative-link pygrep guards + `markdownlint-cli2`) plus companions `dprint.markdown.json` and `.markdownlint-cli2.jsonc`. `cog precommit-apply-template` copies the companions and appends the hook block for every type except `markdown` — guarded on a fresh config copy like the `_spell`/ `_nix` appends — and reports `markdown_hook_appended`.
- The overlay is self-contained: a dedicated `dprint.markdown.json` + `--config` keeps this dprint invocation independent of each type's json-only `dprint.json`, and a distinct `dprint-markdown` hook id avoids colliding with the type's `dprint` hook. No existing type template is edited, and `node`/`sveltekit` (which ship no `dprint.json`) still get markdown formatting.
- The `markdown` type is **excluded** (inverse of the markdown-only `_spell/` overlay): its template already carries the full markdown layer inline plus KB-only extras (md-toc, lychee, spell).
- The generic `.markdownlint-cli2.jsonc` is stricter than the KB one: line length stays off (dprint unwraps), but structural rules (single H1, first-line H1, heading increment) gate.

## Consequences

- Good: one shared markdown source for every code repo; canonical unwrapped markdown and a style gate everywhere. All assets ship in-repo under `skill-refs/templates/pre-commit/` (ADR-0071).
- Good: the overlay is type-independent, so no per-project detection collision.
- Bad: `dprint` becomes a PATH dependency for `node`/`sveltekit`, and the generic markdownlint profile duplicates the KB inline block — a documented drift point.

## Status

Implemented — `lib/commands/cmd_precommit_apply_template.sh`, `skill-refs/templates/pre-commit/_markdown/`, `test/integration/cmd_precommit_apply_template.bats`, and `skills/claude/bootstrap-precommit/SKILL.md`. Builds on ADR-0084 (`_nix/` overlay), ADR-0083 (`_spell/` overlay), ADR-0071 (in-repo assets), and ADR-0081 (KB bootstrap domain).
