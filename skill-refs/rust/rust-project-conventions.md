# Rust project conventions (the way we intend)

The source of truth for how `bootstrap-rust` scaffolds and reconciles a Rust project's own skeleton.
The toolchain and devShell belong to the nix domain (`rust-toolchain.toml`, `flake.nix`, `.envrc`);
this reference covers only the crate skeleton and the optional lint/format/supply-chain config.

## Scaffold from the official cargo CLI

The crate skeleton comes from the real `cargo` CLI, never from a hand-authored `Cargo.toml`. `cargo`
produces a lean, canonical, always-current layout — `Cargo.toml` plus `src/main.rs` (bin) or
`src/lib.rs` (lib). Scaffold with `cargo init` (in place, current directory) rather than `cargo new`
(which creates a subdirectory), so the project keeps the directory it already lives in.

Scaffold **only when the project is not already scaffolded** — when no `Cargo.toml` exists. An existing
crate is reconciled in prose, never re-initialized.

Version control stays with the repo domain: scaffold with `cargo init --vcs none` so cargo never writes
its own `.gitignore`. The Rust `.gitignore` (`/target/`, `**/*.rs.bk`) is delivered by the repo domain
through `cog gitignore-apply --type rust`.

## Defaults are the baseline

Default cargo output — current edition, the resolver cargo picks, a plain `Cargo.toml` — is the
intended baseline. Kind defaults to `bin` unless the intent is a library or a workspace.

- **bin**: an application or CLI. The default.
- **lib**: a reusable library crate.
- **workspace**: a multi-crate repository; scaffold members as needed and keep a virtual
  `[workspace]` root when there is no root package.

## Optional config: add only with a concrete reason

`rustfmt.toml`, `clippy.toml`, and `deny.toml` are **not** created by default. `rustfmt` and `clippy`
ship strong, widely-adopted defaults; an empty or absent config is the intended state. Add one of these
files only when there is an explicit, obvious, widely-adopted reason that measurably improves the
project — for example a documented team style that diverges from `rustfmt` defaults, or a `clippy` lint
level the project has decided to enforce. Absent that, leave the tool on its defaults.

- **`deny.toml`** is the one config with a standing reason to exist: the Rust pre-commit baseline runs a
  `cargo-deny` hook whose licenses check stays disabled until a `deny.toml` allow-list is present.
  Generate it from the official CLI (`cargo deny init`), not by hand, when the project adopts the
  cargo-deny hook.

## Delegate everything else

`bootstrap-rust` owns the crate skeleton and the optional config above, and nothing else. Every other
Rust concern is delivered by its domain owner, driven with `--type rust`:

- `.gitignore` (`/target/`, …) — repo domain (`cog gitignore-apply --type rust`).
- pre-commit hooks (`cargo fmt`, `cargo clippy`, `cargo-nextest`, `cargo-deny`) — pre-commit domain.
- `.editorconfig` (`[*.rs]`) — editorconfig domain.
- cargo task recipes (`cargo build`/`test`/`clippy`) — taskrunner domain.
- CI steps wrapped in `nix develop --command` — CI domain.
- toolchain + devShell (`rust-toolchain.toml`, `flake.nix`, `.envrc`) — nix domain.
