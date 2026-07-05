# Rust publishing conventions (the way we intend)

The source of truth for how `bootstrap-cargo-publish` decides and documents cargo crate publishing.
The crate skeleton and crates.io metadata in `Cargo.toml` belong to `bootstrap-rust`; this reference
covers the publish workflow, the release tooling, authentication policy, and the go/no-go readiness
gates that the publishing worker owns.

## Intent and ownership boundary

`bootstrap-cargo-publish` owns the publish **judgment** layer plus the artifacts that carry it: the
auth-gated helper scripts, `PUBLISHING.md`, `release-plz.toml`, and the optional cargo-dist config.
Everything else stays with its owner:

- crates.io metadata in `Cargo.toml` (`description`, `license`, `repository`, `keywords`,
  `categories`, `readme`, `publish`) — `bootstrap-rust`.
- publish/version task recipes, when a task runner is present — taskrunner domain.
- the release CI workflow file — CI domain.

## Publishing workflow and release tool

`release-plz` is the CI-first default. It opens a release PR that bumps the version and updates the
changelog, `Cargo.toml`, and `Cargo.lock`, then tags, releases, and publishes on merge; it runs
`cargo-semver-checks` natively for library packages. Prefer it whenever the project publishes from CI.

`cargo-release` is the operator-driven local alternative (`cargo release <level> --execute`, dry-run
by default, no release-PR bot). Choose it when the maintainer wants an explicit local release command
and no automation PR.

## Authentication

Default to Trusted Publishing (OIDC) when the project publishes from CI: it removes long-lived token
secrets by exchanging the CI OIDC identity for a short-lived crates.io token. The **first publish is
always manual** — Trusted Publishing is configured on crates.io against an already-existing crate.

Load-bearing nuance for the release CI workflow: a `release-plz` job grants `permissions: id-token:
write`, sets **no** `CARGO_REGISTRY_TOKEN`, and does **not** use `rust-lang/crates-io-auth-action`
(release-plz mints the OIDC-backed token itself). Only a **plain** `cargo publish` workflow uses
`rust-lang/crates-io-auth-action` to mint the token. A long-lived `CARGO_REGISTRY_TOKEN` secret is a
fallback only when OIDC is unavailable or when publishing purely locally.

No skill and no `cog` verb ever reads or writes a credential: the operator configures crates.io auth,
and the only auth check is a configuration check inside the deployed `publish` helper script.

## SemVer gate

For a `lib` crate the SemVer gate is load-bearing: `cargo-semver-checks` (`cargo semver-checks
check-release`) compares the public API against the last published version and is native inside
release-plz. A `bin`-only crate documents a SemVer policy but needs no API check.

## Readiness checks

`cargo publish --dry-run` and `cargo package --list` are the go/no-go checks, run through `cog
cargo-publish-check`. Neither needs auth, so they run before any credential is configured.

## Optional binary distribution

`dist` (cargo-dist) packages application binaries, installers, and GitHub-release artifacts. Offer it
only when the crate is a CLI or application that ships prebuilt binaries; the judgment layer decides
inclusion from the crate kind (`bin`) and the operator's intent. Library-crate publishing to crates.io
never needs it.

External references (optional enhancers): the crates.io Trusted Publishing docs, the Cargo publishing
reference, release-plz.dev, the cargo-release and cargo-semver-checks project READMEs, and the
cargo-dist book. The conventions above are self-contained; the external links only enrich them.
