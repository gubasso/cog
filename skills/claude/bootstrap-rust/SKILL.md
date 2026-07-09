---
name: bootstrap-rust
description: >
  Scaffold a Rust project's own skeleton for the current project: a lean crate
  laid down by the official cargo CLI (Cargo.toml plus src/), scaffolded only
  when the project is not already a crate, plus optional rustfmt/clippy/deny
  config added only with a widely-adopted reason. Delegates deterministic
  scaffold detection and cargo invocation to the cog CLI while keeping kind
  choice and reconciliation judgment in prose; the toolchain, devShell,
  .gitignore, hooks, editorconfig, tasks, and CI stay with their own domains.
  Use when the user says "bootstrap-rust", "set up rust", "rust project",
  "cargo project", or "scaffold rust".
model: opus
effort: low
---

<!-- trigger-tests: "bootstrap-rust", "set up rust", "rust project", "cargo project", "scaffold rust" -->

# Bootstrap Rust Skill

Give the current project its Rust crate skeleton — the files that make it a cargo project — laid down
by the official `cargo` CLI and tuned in prose. The toolchain and devShell belong to the nix domain;
this skill owns only the crate itself and its optional lint/format/supply-chain config.

Principle: the skeleton comes from the real cargo CLI, never hand-authored. `cargo` produces a lean,
canonical, current layout; scaffold only when the project is not already a crate, then add on top only
what a widely-adopted convention justifies. The conventions source of truth is
`$(cog skill-refs path rust/rust-project-conventions.md)`.

## Boundary

This skill owns the crate skeleton (`Cargo.toml`, `src/main.rs` or `src/lib.rs`) and, when justified,
`rustfmt.toml` / `clippy.toml` / `deny.toml`. Everything else is delivered by its domain owner, driven
with `--type rust`, and this skill surfaces fragments to them rather than writing those paths:

- toolchain + devShell (`rust-toolchain.toml`, `flake.nix`, `.envrc`) — nix domain.
- `.gitignore` (`/target/`, …) — repo domain (`cog gitignore-apply --type rust`).
- pre-commit hooks (`cargo fmt`, `cargo clippy`, `cargo-nextest`, `cargo-deny`) — pre-commit domain.
- `.editorconfig` (`[*.rs]`) — editorconfig domain.
- cargo task recipes — taskrunner domain.
- CI steps wrapped in `nix develop --command` — CI domain.

## Inputs

- `$ARGUMENTS`: optional crate `kind` (`bin`, the default, or `lib`) and an optional crate name.
- Current working directory: the target project.

## Cog Contract

`cog` must be installed and on `PATH`; a bare call fails legibly if it is missing. Read the current
scaffold state before deciding anything:

```bash
cog cargo-detect --json
```

It emits `{ok, project_root, scaffolded, kind, edition, configs:{rustfmt_toml, clippy_toml, deny_toml},
cargo_runner, reason}`. `scaffolded` is whether a `Cargo.toml` exists; `kind` is the detected crate
kind (`bin`/`lib`/`workspace`/`none`); `cargo_runner` is how cargo is reachable — `bare` (on PATH),
`direnv` (an `.envrc` that enters the flake), `nix-develop` (a `flake.nix` on a nix host), or `absent`.

Scaffold with the official cargo CLI, guarded and idempotent:

```bash
cog cargo-scaffold-apply --kind "$KIND" --json
```

It runs `cargo init --vcs none --<kind>` **only when `scaffolded=false`**, through the resolved
`cargo_runner`, and passes `--vcs none` so cargo never writes a `.gitignore` (that path stays with the
repo domain). Add `--name <crate>` to override the crate name, and `--deny-init` to also run
`cargo deny init` when the project adopts the cargo-deny hook. It emits `{ok, project_root,
cargo_runner, ran[], skipped[], reason}`, is a no-op on an already-scaffolded project, and fails legibly
(never fabricates a crate) when `cargo_runner=absent`. Treat helper output as mechanics only.

Reconciling an existing crate is judgment: inspect `Cargo.toml` and `src/`, decide any change in prose,
and never re-initialize or blind-overwrite a crate that is already scaffolded.

The `Cargo.toml` `authors` entry comes from the repository's own git identity, never a name or email
guessed from context. Follow the git-identity preflight at
`$(cog skill-refs path bootstrap/git-identity-preflight.md)`: read `cog git-identity check --json`, set
`authors = ["<author_string>"]` from its `author_string` when `ok` is `true`, and pause with the
step-by-step it describes when identity is unset.

## Workflow

1. Run `cog cargo-detect --json`. Read `scaffolded`, `kind`, `edition`, `configs`, and `cargo_runner`.

2. If `scaffolded=true`, reconcile in prose — confirm the crate kind and edition match the intent, note
   any drift, and do **not** re-scaffold. When the brief carries crates.io publishing metadata gaps
   (`authors`, `description`, `license`, `repository`, `keywords`, `readme`), reconcile them into
   `Cargo.toml`, which this skill owns; source `authors` from the git-identity preflight. Skip to step 4.

3. If `scaffolded=false`, resolve the crate kind (`bin` unless the intent is a library or workspace) and
   run `cog cargo-scaffold-apply --kind "$KIND" [--name <crate>] --json`. Modern cargo omits `authors`,
   so set it from the git-identity preflight (`author_string`) once the crate exists. When
   `cargo_runner=absent`, surface that the toolchain is not reachable (enter the nix devShell —
   `direnv allow` or `nix develop` — then retry) rather than inventing a `Cargo.toml`.

4. Decide optional config from `$(cog skill-refs path rust/rust-project-conventions.md)`: `rustfmt` and
   `clippy` stay on their defaults unless there is an explicit, obvious, widely-adopted reason to add a
   config that improves the project. Add `deny.toml` (via `cargo-scaffold-apply --deny-init`) when the
   project adopts the cargo-deny pre-commit hook, since its licenses check stays disabled without one.

5. Surface Rust fragments to their domain owners rather than writing those paths here: the Rust
   `.gitignore` (`/target/`) to the repo domain (`cog gitignore-apply --type rust`), cargo pre-commit
   hooks to the pre-commit domain, `[*.rs]` formatting to the editorconfig domain, cargo task recipes to
   the taskrunner domain, and flake-wrapped cargo steps to the CI domain — each with `--type rust`.

6. Present a summary: the crate kind and edition, whether the skeleton was scaffolded or reconciled, any
   optional config added and why, the fragments handed to other domains, and next steps:

   ```bash
   direnv allow          # trust the .envrc once so cargo is on PATH interactively
   cargo build           # inside the devShell (or: nix develop --command cargo build)
   ```

## Guardrails

- Scaffold only from the official cargo CLI, and only when the project is not already a crate; reconcile
  an existing crate in prose.
- Keep `rustfmt`/`clippy` on their defaults; add a config only with a widely-adopted, improving reason.
- Never write the toolchain/devShell, `.gitignore`, pre-commit, `.editorconfig`, task runner, or CI
  paths — surface fragments to their owners with `--type rust`.
- When cargo is unreachable, report it and stop; never fabricate a `Cargo.toml` or `src/`.
- Do not run git commands unless the operator authorizes it.
