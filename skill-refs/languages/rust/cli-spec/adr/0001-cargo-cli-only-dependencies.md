# ADR-0001 — Manage dependencies through Cargo's CLI only

**Status:** Accepted **Date:** 2026-07-04

## Context

[07 — Dependencies](../07-dependencies.md) historically presented its default crate stack as a hand-written `Cargo.toml` skeleton with pinned version strings. Copying that block by hand pins whatever versions happened to be current when the doc was last edited, skips the lockfile update, and lets contributors (and coding agents) drift `Cargo.toml` out of sync with the resolver. Cargo ships `cargo add`/`cargo remove`/`cargo update`, which fetch the latest SemVer-compatible version, resolve the whole graph, and update `Cargo.toml` + `Cargo.lock` in one step. A downstream project (`podbox`) mandated CLI-only dependency management and is reconciling that rule back into this spec.

## Decision

All dependency changes — add, remove, feature toggles, version bumps — go through `cargo add`, `cargo remove`, and `cargo update`. Contributors and agents must not hand-edit dependency names, versions, or feature lists in `Cargo.toml`. `Cargo.lock` is committed for binaries (not for libraries) and kept in sync by those commands. The existing "pin major in `Cargo.toml`, let `Cargo.lock` pin exact" policy is unchanged; it now describes the output of `cargo add` rather than a hand-written table.

## Consequences

- [07 — Dependencies](../07-dependencies.md) gains an `## Adding dependencies` section stating the mandate; its "Cargo.toml skeleton" now hand-authors only `[package]`/`[[bin]]`/`[profile.release]` and installs crates via `cargo add`, with the resolved version block relabelled "illustrative only — install via `cargo add`".
- [`templates/Cargo.toml.template`](../templates/Cargo.toml.template) drops its hardcoded `[dependencies]`/`[dev-dependencies]` blocks in favour of a comment pointing scaffolding agents at the documented `cargo add` commands before first build.
- Downside: `Cargo.toml` diffs are produced by tooling rather than authored, so reviewers can no longer eyeball a curated version block in the doc; they must read the `cargo add` command list and the resulting lockfile instead.

## Alternatives considered

- **Keep the hand-written skeleton.** Rejected: it re-pins stale versions on every copy and lets `Cargo.toml` and `Cargo.lock` diverge.
- **Allow hand-edits but require `cargo update` afterwards.** Rejected: it relies on a discipline step that is easy to skip and hard to enforce for agents; `cargo add` makes the resolve-and-lock atomic.
