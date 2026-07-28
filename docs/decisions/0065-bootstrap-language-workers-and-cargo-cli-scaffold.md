# ADR-0065: Bootstrap language workers scaffold from the official CLI

## Context and Problem Statement

The `bootstrap` family models cross-cutting **domains** (precommit, editorconfig, nix, repo, ci, taskrunner), each language-orthogonal and already `--type rust`-aware. A "bootstrap a Rust project the way we intend" request has no home: the toolchain and devShell already belong to the nix domain (`rust-toolchain.toml`, `flake.nix`), yet the crate skeleton (`Cargo.toml`, `src/`) and optional `rustfmt`/`clippy`/`deny` config are owned by no domain and have no template.

## Considered Options

- Register Rust as a 7th `cog bootstrap-audit` domain.
- Add `bootstrap-rust` as a conditional **language** worker that owns only the unowned crate slice.
- Ship opinionated `Cargo.toml`/`rustfmt.toml`/`clippy.toml` templates like the other domains.

## Decision Outcome

Chosen option: **conditional language worker + official-CLI scaffold** — `bootstrap-rust` is a language worker (not a domain): dispatched by the orchestrator only when `cog classify-project` reports Rust, owning the crate skeleton plus optional config, and delegating every other concern to its domain owner with `--type rust`. It is deliberately **not** a `bootstrap-audit` domain, so the audit's every-domain-in-scope matrix stays language-orthogonal (Rust never reads as "missing" on a non-rust project). The skeleton is laid down by the real `cargo` CLI (`cargo init --vcs none`), guarded to run only when unscaffolded; `rustfmt`/`clippy` stay on defaults, and `deny.toml` comes from `cargo deny
init` only when the cargo-deny hook needs it. New `cog` mechanics: `cargo-detect` and `cargo-scaffold-apply` (with `lib/functions/fn_cargo.sh`).

## Consequences

- Good: no hand-authored manifests to rot; boundaries stay clean (`--vcs none` leaves `.gitignore` to the repo domain); the audit model is untouched; the pattern generalizes to future language workers.
- Bad: a distinct dispatch axis (language vs domain) the orchestrator must sequence — a Rust "Wave 0" scaffolds before the type-sensitive detectors resolve `--type rust`.

## Status

Implemented — `skills/claude/bootstrap-rust/SKILL.md`, `lib/commands/cmd_cargo_detect.sh`, `lib/commands/cmd_cargo_scaffold_apply.sh`, `lib/functions/fn_cargo.sh`, `skill-refs/rust/rust-project-conventions.md`, and the `bootstrap` orchestrator wiring.
