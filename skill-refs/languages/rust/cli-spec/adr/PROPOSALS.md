# ADR Proposals (backlog)

Un-numbered proposals awaiting a decision. Each is a candidate ADR: when accepted it graduates to the next `NNNN-kebab-title.md` file in this directory (see [README](./README.md) for the format). Until then it stays here with **Status: Proposed** and a short rationale. Do not treat these as adopted spec rules.

## P1 — Recommend `miette` 7.x for rich user-facing diagnostics

**Status:** Proposed **Date:** 2026-07-04

`miette` 7.x renders source-span-annotated, colorized diagnostics (à la `rustc`) for user-facing errors — a step up from plain `anyhow` chains when the CLI parses user-authored input (config, DSLs, query strings) and wants to point at the offending span. Proposal: add it to [07 — Dependencies](../07-dependencies.md) "Conditional adds" as the human-facing diagnostic option, gated to human-facing CLIs, while keeping `thiserror` + `anyhow` as the default stack and `color-eyre` as the dev-build pretty-printer. Rationale: it is additive (implements `std::error::Error`), so it layers on the existing error stack without replacing it.

## P2 — Note `etcetera` (`choose_app_strategy`) as a `directories` alternative

**Status:** Proposed **Date:** 2026-07-04

`etcetera`'s `choose_app_strategy` lets a CLI force XDG semantics on every platform (instead of the platform-native dirs `directories` returns), which some tools prefer for cross-platform consistency. Proposal: [05 — Config](../05-config.md) and [07 — Dependencies](../07-dependencies.md) note `etcetera` as a trending alternative to `directories` for projects that want XDG everywhere. Rationale: it is a genuine behavioural difference (uniform XDG vs native dirs), not a drop-in, so it warrants a flag rather than a default swap — `directories` stays the recommended default.

## P3 — Devcontainer lockfile-by-default as a wrapping consideration

**Status:** Proposed **Date:** 2026-07-04

Dev Containers now generate `.devcontainer-lock.json` by default and `@devcontainers/cli` exposes `outdated`/`upgrade` subcommands. Proposal: note this in the CLI-wrapper guidance so a Rust CLI that wraps `@devcontainers/cli` treats the lockfile and its `outdated`/`upgrade` verbs as first-class (pass-through, don't reinvent). Rationale: mirrors the `Cargo.lock`/`cargo update` discipline this shelf already mandates — the wrapped tool now has the same resolve-and-lock model to respect.

## P4 — Offer a non-strict `deny_unknown_fields` config variant

**Status:** Proposed **Date:** 2026-07-04

[05 — Config](../05-config.md) puts `#[serde(default, deny_unknown_fields)]` on the top-level `Config` struct so TOML typos fail loudly. That conflicts with a forward-compat product contract where unknown config keys must be **preserved and ignored** (so older binaries tolerate keys added by newer ones). A downstream project (`podbox`) deliberately overrode `deny_unknown_fields` for exactly this reason. Proposal: 05-config note the trade-off explicitly and offer a non-strict variant (drop `deny_unknown_fields`, optionally capture extras via `#[serde(flatten)] extra:
Map<String, Value>`, and/or gate strictness behind the `--config-strict` toggle the general checklist already mentions). Rationale: strict-by-default is right for most CLIs, but "reject vs preserve unknown keys" is a real product decision the spec should surface rather than force.

## P5 — Language-agnostic dependency-hygiene ADR for `cli-design`

**Status:** Proposed **Date:** 2026-07-04

The `cli-design` shelf has no `adr/` directory today. The cargo-CLI-only rule captured in [ADR-0001](./0001-cargo-cli-only-dependencies.md) generalizes (`cargo add` / `uv add` / `go get` — resolve-and-lock, never hand-edit pins); the language-agnostic checklist item was already added to `cli-design/99-checklist.md`. Proposal: **if/when** `cli-design` adopts an `adr/` convention, record a language-agnostic dependency-hygiene ADR there. Rationale: this is a cross-language principle, but this shelf must not create an `adr/` directory in `cli-design` before that shelf decides to adopt one — so it stays a proposal here.
