# ADR-0093: skill-refs Is the Single Runtime-Injection Mechanism; Runtime-YAML-Render Retired

## Context and Problem Statement

[ADR-0089](./0089-gates-as-skill-refs-references.md) retired **stamp + lint** as a second mechanism for shared cross-skill text and standardized on skill-refs. A third mechanism survived that pass: **runtime YAML render** — [ADR-0087](./0087-runtime-rendered-ask-flag-instructions.md)'s `cog ask-flag render --flag <key>`, reading prose paragraphs from `data/ask-flags/instructions.yaml`.

ADR-0087 justified itself on conditionality: text that "enters context only when a flag actually fires", contrasted with `cog gate` ("whose text must be visible in the file"). That premise does not hold. Conditionality is a property of the skill's `if`, not of the storage backend — and the repository already demonstrated it, in one file, on adjacent lines:

```text
- **If `WEB_SEARCH = true`**, read `$(cog skill-refs path research/primary-source-verification.md)` and append its content …
- **If `REAL_WORLD = true`**, run `cog ask-flag render --flag real-world` and append its stdout …
```

Two flags with identical semantics — _flag fires → obtain canonical paragraph → append verbatim to a delegated sub-prompt_ — served by two different backends, in both `ask` twins. [ADR-0088](./0088-primary-source-verification-shared-reference.md) had already migrated `web-search` out of `data/ask-flags` and amended ADR-0087, leaving `real-world` as the table's only row. Maintaining a command, a loader module, a data table, a test file, and install wiring for one paragraph is the same redundancy ADR-0089 spent a decision removing.

The asymmetry is not only in part count. Prose in `skill-refs/**/*.md` is covered by four quality gates — `dprint-markdown`, `markdownlint-cli2` (including the `relative-links` rule), the bare-relative-link pygrep guards, and the dedicated `skill-refs-lint` hook running the self-containment golden rules. Identical prose inside a YAML folded scalar is covered by `check-yaml` (syntax only) and `editorconfig-checker`. No `cog skill-lint` rule referenced `ask-flag` at all.

## Considered Options

- Keep both mechanisms, with a documented boundary (status quo after ADR-0088).
- Generalize the render mechanism into `cog skill-flag render --skill <s> --flag <f>` so every skill family can express optional behavior as YAML data.
- Retire runtime YAML render; standardize on skill-refs as the single runtime-injection mechanism.

## Decision Outcome

Chosen option: **retire runtime YAML render**. `skill-refs/**/*.md` is the single mechanism for prose a model reads at runtime, conditional or not. Flag-conditionality lives in the skill's `if`, never in the storage backend.

The normative boundary, stated so a maintainer can apply it without deliberation:

> **Structured data the CLI computes over → `data/*.yaml`. Prose a model reads → `skill-refs/**/*.md`.**
>
> Test: does any `cog` code branch, sort, compare, or validate against this value? If yes → `data/`. If the only operation is "hand these words to a model" → `skill-refs/`.

Under this rule `data/model-effort/*/tiers.yaml`, `data/power-grade/**`, `data/skill-class/contracts.yaml`, `data/spec-leakage/patterns.yaml`, and a future `data/pipelines/` are unambiguously data; a research directive injected into a sub-prompt is unambiguously prose.

The generalization option is rejected for the same reason: a `cog skill-flag render` would reintroduce the mechanism this ADR retires. Optional skill behavior is expressed as `If FLAG = true, read $(cog skill-refs path …)`, which is what `ask -w` already did.

## Consequences

- Good: one mechanism for runtime-injected prose, completing the consolidation ADR-0089 began.
- Good: the migrated directive gains four quality gates it did not have in YAML — a strict increase in enforcement, with no new lint rule written.
- Good: adding a directive is now `git add skill-refs/<area>/<name>.md`; `install.sh` already copies the whole tree, so no deploy wiring per addition. ADR-0087's own recorded downside ("a new `data/` table adds explicit install wiring that must not be forgotten") is removed.
- Good: `data/` regains a clean charter — every remaining table is genuinely structured.
- Good: the directive is a real file path, so it appears in transcripts, resolves under `grep -r`, and carries `git blame` history.
- Bad: `cog ask-flag` disappears from the CLI with no deprecation alias; an alias would reintroduce the retired mechanism.
- Bad: machine enumeration (`cog ask-flag list --json`) and YAML-key validation are gone. Neither had a consumer, and filesystem existence — checked at runtime by `cog skill-refs path` (fails closed with `InputNotFound`) and at commit time by markdownlint's `relative-links` rule — is the stronger registry.

## Status

Implemented. `data/ask-flags/`, `lib/commands/cmd_ask_flag.sh`, `lib/functions/fn_ask_flag.sh`, and `test/unit/cmd_ask_flag.bats` are removed; the directive lives at `skill-refs/research/real-world-exemplars.md`; `skills/claude/ask/SKILL.md` and `skills/codex/ask/SKILL.md` read it through `cog skill-refs path`, so their `-w` and `-r` paths are now structurally identical. Install wiring, `bin/cog` sourcing, completions, man page, CLI reference, and help snapshots are updated. `install.sh` carries no `ask-flags` residue at all; an install predating this ADR keeps a stale `$XDG_DATA_HOME/cog/data/ask-flags/` that nothing reads and that `uninstall.sh` prunes with the rest of the data tree.

Supersedes [ADR-0087](./0087-runtime-rendered-ask-flag-instructions.md). Extends [ADR-0089](./0089-gates-as-skill-refs-references.md); references [ADR-0023](./0023-skill-refs-unified-resource-sot.md), [ADR-0052](./0052-cog-data-directory-and-format.md), [ADR-0088](./0088-primary-source-verification-shared-reference.md), and [ADR-0019](./0019-lean-positive-skill-prose.md).
