# ADR-0084: Nix pre-commit layer (universal overlay + nix fallback type)

## Context and Problem Statement

Every bootstrapped project now carries a per-project Nix devShell (`flake.nix` + `.envrc` via direnv/nix-direnv, ADR for the devShell standard). Those Nix sources were ungoverned at the pre-commit level: no template formatted or linted `flake.nix`/`*.nix`, and there was no template for a Nix-primary repo (a flake defining hosts/modules/packages) at all. The pre-commit templates already ship the generic hygiene and secret hooks (`pre-commit-hooks`, `detect-private-key`, `ripsecrets`, `gitleaks`, `typos`, `committed`, `editorconfig-checker`, `dprint`), so the only missing, Nix-specific gates were `nixfmt` (format), `statix`/`deadnix` (lint), and `nix flake
check` (eval).

## Considered Options

- Inline the Nix hooks into each of the eight per-type configs (duplication across templates).
- A shared `_nix/` overlay appended to every deployed config (mirrors the `_spell/` overlay), plus a dedicated `nix` type template for Nix-primary repos.
- A `nix` type only, so a rust/python project's `flake.nix` stays unlinted.
- A git-hooks.nix / flake-native pre-commit integration instead of a standalone config.

## Decision Outcome

Chosen: **a universal `_nix/` overlay plus a `nix` fallback type**.

- `skill-refs/templates/pre-commit/_nix/` holds `hook.pre-commit.yaml` (the Nix hook block) and a `statix.toml` companion. `cog precommit-apply-template` copies `statix.toml` and appends the hook block to the freshly-copied config for **every** type — guarded on a fresh config copy, like the `_spell` append — and reports `nix_hook_appended`. Every project has a flake, so every project's Nix sources are governed.
- Tools run as `repo: local` / `language: system` off PATH, the same model as the existing `dprint`/`cargo-fmt` hooks. The bootstrap-nix flake templates therefore ship `nixfmt-rfc-style`/`statix`/`deadnix` (and set `formatter`) in the devShell so the hooks resolve.
- Stage split matches the reference setups: `nixfmt` (format, auto-fix), `statix check` and `deadnix --fail` (report-only gates) run at `pre-commit`; `nix flake check` runs at `pre-push`, scoped to `\.nix$` so it stays inert when the flake does not change.
- A `nix` type template serves Nix-primary repos (housekeeping + shell + secrets + `committed`), with the Nix hooks arriving from the overlay, not inlined. It resolves only as a **dominance fallback** (like `markdown`): `classify-project` reports the `nix` language only when `*.nix` files are the plurality of code, and `detect_matches` matches `nix` only when no code-language template matched — so a lone `flake.nix` never collides with the repo's real language.

Inlining was rejected for duplication and drift; a `nix`-only type was rejected because it leaves non-Nix projects' flakes unlinted; git-hooks.nix was rejected to keep templates driven by the standard `pre-commit` CLI and a committed `.pre-commit-config.yaml` (portable to non-Nix contributors). Formatter choice is `nixfmt-rfc-style` (RFC 166, the nixpkgs standard); lint stays report-only (no `--edit`/`fix`) to avoid surprise code deletion on commit.

## Consequences

- Good: one shared source for the Nix hooks; every project's flake is formatted and linted; a first-class Nix-primary template. All assets ship in-repo under `skill-refs/templates/pre-commit/` (ADR-0071).
- Good: the overlay is type-independent, so no per-project detection collision despite every repo carrying a `flake.nix`.
- Bad: a new `_nix/` overlay convention the template-refresh routine must respect, and a bootstrap-nix ↔ bootstrap-precommit coupling (the devShell must provide the hook tools).

## Status

Implemented — `lib/commands/cmd_precommit_apply_template.sh`, `lib/functions/fn_template.sh`, `lib/commands/cmd_classify_project.sh`, `skill-refs/templates/pre-commit/_nix/`, `skill-refs/templates/pre-commit/nix/`, `skill-refs/templates/nix/*/flake.nix`, `skills/claude/bootstrap-precommit/SKILL.md`, and `skills/claude/bootstrap-nix/SKILL.md`. Builds on ADR-0083 (`_spell/` overlay), ADR-0082 (reliable classification), and ADR-0008 (skill/script boundary).
