---
name: bootstrap-rust
description: >
  Scaffold a Rust project's crate skeleton with the official cargo CLI, and —
  when the intent is publishing — set up crates.io release: auth-gated
  publish/dry-run/release scripts, a PUBLISHING.md runbook, and optional
  release-plz/cargo-dist config. Use when the user says "bootstrap-rust", "set
  up rust", "rust project", "cargo project", "scaffold rust", "set up cargo
  publishing", "publish to crates.io", "release-plz", or "cargo-dist".
model: opus
effort: low
argument-hint: "[bin|lib] [crate-name] [--publish] [release-plz|cargo-release]"
---

<!-- trigger-tests: "bootstrap-rust", "set up rust", "rust project", "cargo project", "scaffold rust", "set up cargo publishing", "publish to crates.io", "release-plz", "cargo-dist" -->

# Bootstrap Rust

Give the project its Rust crate skeleton — the files that make it a cargo project — laid down by the official `cargo` CLI and tuned in prose. The skeleton comes from the real cargo CLI, never hand-authored: cargo produces a lean, canonical, current layout. Scaffold only when the project is not already a crate, then add on top only what a widely-adopted convention justifies, per `$(cog skill-refs path rust/rust-project-conventions.md)`.

**Publishing is an opt-in branch**, taken when the intent involves crates.io, `cargo publish`, `release-plz`, `cargo-release`, or `cargo dist`. It layers the release workflow onto the crate this skill already owns. A project that never publishes never pays for it.

Owning both is what makes the crates.io metadata correct: `Cargo.toml` is written here, and the publish branch is what knows which fields crates.io rejects a publish without.

## Boundary

This skill owns the crate skeleton (`Cargo.toml`, `src/main.rs` or `src/lib.rs`), optional `rustfmt.toml` / `clippy.toml` / `deny.toml`, and — on the publish branch — `scripts/publish`, `scripts/publish-dry`, `scripts/release`, `PUBLISHING.md`, `release-plz.toml`, and the optional `dist-workspace.toml`.

Everything else belongs to its domain owner, driven with `--type rust`; surface fragments to them rather than writing those paths:

- toolchain + devShell (`rust-toolchain.toml`, `flake.nix`, `.envrc`) — nix domain.
- `.gitignore` (`/target/`) — repo domain (`cog gitignore-apply --type rust`).
- pre-commit hooks (`cargo fmt`, `cargo clippy`, `cargo-nextest`, `cargo-deny`) and `[*.rs]` formatting — lint domain.
- cargo and publish/version task recipes — taskrunner domain.
- CI steps wrapped in `nix develop --command`, and the release-plz job — CI domain.

## Crate skeleton

```bash
cog cargo-detect --json
```

Read `scaffolded` (whether a `Cargo.toml` exists), `kind` (`bin`/`lib`/`workspace`/`none`), `edition`, `configs`, and `cargo_runner` — how cargo is reachable: `bare` (on PATH), `direnv`, `nix-develop`, or `absent`.

- **`scaffolded=false`** → resolve the kind (`bin` unless the intent is a library or workspace) and scaffold:

  ```bash
  cog cargo-scaffold-apply --kind "$KIND" [--name <crate>] [--deny-init] --json
  ```

  It runs `cargo init --vcs none --<kind>` through the resolved runner **only when `scaffolded=false`**, so it is a no-op on an existing crate. `--vcs none` keeps cargo from writing a `.gitignore`, which belongs to the repo domain. `--deny-init` also runs `cargo deny init`, which the cargo-deny hook needs — its licenses check stays disabled without a `deny.toml`.

- **`scaffolded=true`** → reconcile in prose. Confirm the kind and edition match the intent and note any drift. Never re-initialize or blind-overwrite a crate that already exists.

- **`cargo_runner=absent`** → report that the toolchain is unreachable (enter the devShell: `direnv allow`, or `nix develop`) and stop. Never fabricate a `Cargo.toml` or `src/`.

Modern cargo omits `authors`. Set it from the repository's own git identity, never a name or email guessed from context: follow `$(cog skill-refs path bootstrap/git-identity-preflight.md)`, read `cog git-identity check --json`, and set `authors = ["<author_string>"]` from its `author_string` when `ok` is `true`, pausing with the step-by-step it describes when identity is unset.

Keep `rustfmt` and `clippy` on their defaults unless there is an explicit, widely-adopted reason that a config improves the project.

## Publishing

Taken only on publishing intent. Follow the shared routine at `$(cog skill-refs path bootstrap/domain-worker-routine.md)` for the `cargo-publish` domain — the freshness type is always `rust`, since cargo-publish is Rust-only with one template set:

```bash
cog bootstrap-template-review check --domain cargo-publish --type rust --json
```

A fresh review means reuse the cached `summary` and go straight to deploying; stale or missing means research current crates.io / release-plz / cargo-dist practice against `$(cog skill-refs path rust/rust-publish-conventions.md)`, update `skill-refs/templates/cargo-publish/` when justified, and `stamp` before reconciling.

Read the landscape:

```bash
cog cargo-publish-detect --json
```

`is_publishable` is false when there is no `Cargo.toml` or `publish = false` is set. `ci_provider`, `release_tool`, `semver_tool`, and `ships_binaries` each carry a presence flag plus the `signals` that matched. `metadata` is pure manifest inspection, so gaps surface even without a reachable cargo.

Then decide, in this order:

1. **Metadata.** `has_description` and `has_license` are publish-rejecting — crates.io hard-rejects a publish lacking either. `has_repository`, `keywords_count`, and `categories_count` (canonical slugs, or the publish fails) drive discovery. Fix the gaps directly in `Cargo.toml`.

2. **Auth mode.** Trusted Publishing/OIDC when `ci_provider` is `github` or `gitlab`, else a local token via `cargo login`. The first publish is always manual, with a `publish-new`, exact-crate-scoped, shortest-expiry token that is revoked once OIDC is live.

3. **Release tool.** `release-plz` by default when CI is present; `cargo-release` for an explicit local/no-bot preference.

4. **Binary distribution.** Include cargo-dist (`--with-dist`) when `ships_binaries.hint` is set and the operator confirms the crate ships prebuilt binaries; library-only crates never need it. It produces its own `.github/workflows/release.yml` (shell/PowerShell/Homebrew-tap installers, and `cargo-binstall` then works from GitHub Releases) — a **separate file** from `release-plz.yml`, so the crates.io Trusted Publisher keeps matching the actual release-plz filename.

5. **SemVer gate.** Load-bearing when `kind=lib` (`cargo-semver-checks`, native in release-plz). A bin-only crate documents a policy but needs no API check.

Deploy, with `--doc-dir docs` when a `docs/` directory exists and `--doc-dir .` otherwise:

```bash
cog cargo-publish-apply --doc-dir <docs|.> [--with-release-plz] [--with-dist] --conflict "$POLICY" --json
```

Scripts land executable. `--with-dist` lays down `dist-workspace.toml` only — generating `release.yml` (`dist init` the first time, `dist generate` after config edits) is a manual operator follow-up.

Gate readiness last; it needs a reachable cargo, not a token:

```bash
cog cargo-publish-check --json
```

It runs `cargo publish --dry-run` and `cargo package --list`. Review the `package_list` for non-build-input junk (`docs/`, `.github/`, `scripts/`, `release-plz.toml`, `dist-workspace.toml`, `justfile`, `flake.nix`, editor and lint configs) and add an `exclude` denylist to keep the `.crate` lean. Watch the SPDX footgun: an `include` allowlist must name `README` and `LICENSE` explicitly, because neither is auto-included when `license` is an SPDX expression. `metadata.has_exclude`/`has_include` show whether trimming is already configured.

**The crates.io auth check is a deliberate exception that lives inside the deployed `publish` script.** There is no `cog cargo-publish-auth` command, and neither this skill nor any `cog` verb ever reads, echoes, or inspects a credential. The dry-run path is never auth-gated, and a real `cargo publish` is never run from here.

## Close

Report the crate kind and edition, whether the skeleton was scaffolded or reconciled, any optional config added and why, and the fragments handed to other domains. On the publish branch, add the auth mode, release tool, and cargo-dist decision (with the `dist init`/`dist generate` follow-up when selected), the deployed files, the readiness result, the tarball-hygiene findings, and the first-publish-is-manual reminder.

```bash
direnv allow          # trust the .envrc once so cargo is on PATH interactively
cargo build           # inside the devShell (or: nix develop --command cargo build)
```

Treat cargo-dist's generated `release.yml` as an artifact: never hand-edit or template it, keep it separate from `release-plz.yml`, and register only `release-plz.yml` with the crates.io Trusted Publisher.

Run no git command unless the operator authorizes it.
