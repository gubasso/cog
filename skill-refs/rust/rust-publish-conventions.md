# Rust publishing conventions (the way we intend)

The source of truth for how `bootstrap-rust` decides and documents cargo crate publishing: the publish workflow, the release tooling, the authentication policy, and the go/no-go readiness gates.

## Intent and ownership boundary

`bootstrap-rust` owns the publish **judgment** layer plus the artifacts that carry it: the auth-gated helper scripts, `PUBLISHING.md`, `release-plz.toml`, and the optional cargo-dist config. It also owns the crate skeleton and the crates.io metadata in `Cargo.toml` (`description`, `license`, `repository`, `keywords`, `categories`, `readme`, `publish`), so a metadata gap found during the readiness gate is fixed in place rather than handed off.

Two things stay with their own owner:

- publish/version task recipes, when a task runner is present — taskrunner domain.
- the release CI workflow file — CI domain.

## Crate metadata gate

crates.io validates `[package]` metadata at publish time, and a missing required field is the single most common first-publish blocker. `description` **and** a license (`license` SPDX expression or `license-file`) are **required** — crates.io hard-rejects a publish that lacks either. `repository` warns and drives the crate-page link; `keywords` (≤5, ≤20 chars each) and `categories` improve discovery, and `categories` must match the canonical crates.io slugs exactly or the publish fails. `cog cargo-publish-detect` reports these as a read-only `metadata` block so gaps surface even when cargo is unreachable. Fix any gap directly in `Cargo.toml`, which the same skill owns.

## Tarball hygiene

Keep the published `.crate` lean: Cargo packages the whole working tree by default, so project docs, CI, and dev tooling ship as dead weight unless trimmed. Prefer an `exclude` denylist (robust against dropping future `src/` files) over an `include` allowlist, and exclude non-build inputs such as `/docs`, `/.github`, `/scripts`, `/release-plz.toml`, `/dist-workspace.toml`, `/justfile`, `/flake.nix`, and editor/lint configs. Footgun: with an SPDX `license` expression, Cargo does **not** auto-include a plain `README` or `LICENSE`, so an `include` allowlist must list them explicitly. crates.io enforces a hard 10 MB limit; for a binary crate no consumer ever reads the tarball, so docs and tooling are pure waste. `cargo package --list` (via `cog cargo-publish-check`) shows exactly what would ship; add the recommended `exclude` list to `Cargo.toml` directly.

## Publishing workflow and release tool

Version source of truth (shared model, see `release/release-workflow-conventions.md`): `Cargo.toml` `[package] version` is the committed authoring source of truth, bumped in place by the release tool; the annotated `vX.Y.Z` tag is derived from it and is the published record.

`release-plz` is the CI-first default. It opens a release PR that bumps the version and updates the changelog, `Cargo.toml`, and `Cargo.lock`, then tags, releases, and publishes on merge; it runs `cargo-semver-checks` natively for library packages. Prefer it whenever the project publishes from CI.

`cargo-release` is the operator-driven local alternative (`cargo release <level> --execute`, dry-run by default, no release-PR bot). Choose it when the maintainer wants an explicit local release command and no automation PR.

## Authentication

Default to Trusted Publishing (OIDC) when the project publishes from CI: it removes long-lived token secrets by exchanging the CI OIDC identity for a short-lived crates.io token. The **first publish is always manual** — Trusted Publishing is configured on crates.io against an already-existing crate.

Load-bearing nuance for the release CI workflow: a `release-plz` job grants `permissions: id-token:
write`, sets **no** `CARGO_REGISTRY_TOKEN`, and does **not** use `rust-lang/crates-io-auth-action` (release-plz mints the OIDC-backed token itself). Only a **plain** `cargo publish` workflow uses `rust-lang/crates-io-auth-action` to mint the token. A long-lived `CARGO_REGISTRY_TOKEN` secret is a fallback only when OIDC is unavailable or when publishing purely locally.

Token-scope hygiene for the manual first publish: create one narrow, per-crate token scoped to the exact crate name with the `publish-new` endpoint scope (the first upload creates the crate; `publish-update` does not apply yet), pick the shortest expiry offered, and revoke it once OIDC is live. A local escape-hatch token uses `publish-update`; avoid the unscoped `legacy` scope.

No skill and no `cog` verb ever reads or writes a credential: the operator configures crates.io auth, and the only auth check is a configuration check inside the deployed `publish` helper script.

## SemVer gate

For a `lib` crate the SemVer gate is load-bearing: `cargo-semver-checks` (`cargo semver-checks
check-release`) compares the public API against the last published version and is native inside release-plz. A `bin`-only crate documents a SemVer policy but needs no API check.

## Readiness checks

`cargo publish --dry-run` and `cargo package --list` are the go/no-go checks, run through `cog
cargo-publish-check`. Neither needs auth, so they run before any credential is configured.

## Binary distribution (cargo-dist)

`dist` (cargo-dist) packages application binaries, installers, and GitHub-release artifacts — a first-class **conditional** step. Offer it only when the crate is a CLI or application that ships prebuilt binaries; the judgment layer decides inclusion from the crate kind (`bin`) and the operator's intent. Library-crate publishing to crates.io never needs it. It builds shell/PowerShell/Homebrew-tap installers and attaches them to each GitHub Release; `cargo-binstall` then works automatically from those releases. AUR, OBS/zypper, and Homebrew (beyond the generated tap) are downstream/manual channels that consume the tagged Release — not auto-generated pipelines.

**Workflow-file naming (load-bearing).** `dist` generates its own workflow at `.github/workflows/release.yml` — a **distinct file** from the release-plz workflow, which must be `release-plz.yml`. The crates.io Trusted Publisher matches on the workflow _filename_ and must name `release-plz.yml` (the file that actually publishes), never cargo-dist's `release.yml` (which only builds binaries and does not publish). `cog cargo-publish-apply --with-dist` lays down `dist-workspace.toml` only; the operator generates `release.yml` with `dist init` / `dist generate`. Treat that workflow as an artifact — regenerate from config, never hand-edit — and keep it a separate file from `release-plz.yml`.

External references (optional enhancers): the crates.io Trusted Publishing docs, the Cargo publishing reference, release-plz.dev, the cargo-release and cargo-semver-checks project READMEs, and the cargo-dist book. The conventions above are self-contained; the external links only enrich them.
