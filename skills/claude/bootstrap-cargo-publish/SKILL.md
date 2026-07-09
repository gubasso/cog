---
name: bootstrap-cargo-publish
description: >
  Set up cargo crate publishing for the current project: a conditional Rust +
  publishing bootstrap worker, sibling of bootstrap-rust. Deploys auth-gated
  publish/dry-run/release helper scripts, a PUBLISHING.md runbook, and optional
  release-plz/cargo-dist config, and owns the publish-judgment layer (auth mode,
  release tool, semver gating, optional binary distribution, go/no-go readiness).
  Delegates deterministic detection and template copying to the cog CLI; the auth
  check lives only inside the deployed scripts, never in a skill or in cog. Use
  when the user says "bootstrap-cargo-publish", "set up cargo publishing",
  "publish to crates.io", "cargo publish setup", "release-plz", or "cargo-dist".
model: opus
effort: low
---

<!-- trigger-tests: "bootstrap-cargo-publish", "set up cargo publishing", "publish to crates.io", "cargo publish setup", "release-plz", "cargo-dist" -->

# Bootstrap Cargo Publish Skill

Set up cargo crate publishing for the current project — the release workflow, the auth-gated helper
scripts, and the `PUBLISHING.md` runbook that make the crate publishable and keep releasing it
repeatable. This is a conditional **Rust + publishing** worker, sibling of `bootstrap-rust`: the crate
skeleton and its crates.io metadata stay with `bootstrap-rust`, and this skill owns the publish
judgment on top.

Principle: deterministic detection and template copying come from the cog CLI; the tooling and auth
choices are prose judgment grounded in `$(cog skill-refs path rust/rust-publish-conventions.md)`. The
crates.io auth check is a single deliberate exception — it lives inside the deployed `publish` helper
script, so no skill and no `cog` verb ever reads a credential.

## Boundary

This skill owns the publish-judgment layer plus the artifacts that carry it: the auth-gated helper
scripts (`scripts/publish`, `scripts/publish-dry`, `scripts/release`), `PUBLISHING.md`, `release-plz.toml`,
and the optional `dist-workspace.toml`. Everything else is delivered by its owner and surfaced as a
fragment rather than written here:

- crates.io metadata in `Cargo.toml` (`authors`, `description`, `license`, `repository`, `keywords`,
  `readme`, `publish`) — `bootstrap-rust` (it sources `authors` from the repo's git identity).
- publish/version task recipes, when a task runner is present — taskrunner domain (`--type rust`).
- the release CI workflow (release-plz job, OIDC permissions, optional `dist` job) — CI domain
  (`--type rust`).

The auth gate is an intentional project-helper behavior inside the deployed `publish` script; `cog` and
this skill's prose never inspect a credential env var or file.

## Inputs

- `$ARGUMENTS`: optional release-tool preference (`release-plz` or `cargo-release`), binary-distribution
  intent (whether the crate ships prebuilt binaries), and a local-only preference.
- Current working directory: the target project.

## Cog Contract

`cog` must be installed and on `PATH`; a bare call fails legibly if it is missing. Read the publishing
landscape before deciding anything:

```bash
cog cargo-publish-detect --json
```

It emits `{ok, project_root, crate_kind, is_publishable, publishable_reason, ci_provider, release_tool,
semver_tool, ships_binaries, metadata, cargo_runner, reason}`: `crate_kind` is
`bin`/`lib`/`workspace`/`none`; `is_publishable` is false when there is no `Cargo.toml` or
`publish = false` is set; `ci_provider` is `github`/`gitlab`/`none`;
`release_tool`/`semver_tool`/`ships_binaries` carry a presence flag plus the `signals` that matched.
`metadata` is pure manifest inspection — `{has_description, has_license, has_repository, has_readme,
has_exclude, has_include, keywords_count, categories_count}` — so metadata gaps surface without a
reachable cargo.

Gate go/no-go readiness with the dry-run checks — no token required:

```bash
cog cargo-publish-check --json
```

It runs `cargo publish --dry-run` and `cargo package --list` through the resolved cargo runner and emits
`{ok, cargo_runner, dry_run, package_list, reason}`; when cargo is unreachable it reports
`cargo_runner=absent` rather than running anything.

Deploy the helper scripts and runbook:

```bash
cog cargo-publish-apply --doc-dir <docs|.> [--with-release-plz] [--with-dist] --conflict <policy> --json
```

It copies `scripts/publish`, `scripts/publish-dry`, `scripts/release`, and `PUBLISHING.md` into the
project (scripts land executable), adds `release-plz.toml` with `--with-release-plz` and
`dist-workspace.toml` with `--with-dist`, and honors `--conflict overwrite|skip|abort`.

There is no `cog cargo-publish-auth` command. The crates.io auth check is a deliberate script-local
exception inside the deployed `publish` script; no `cog` verb and no skill prose reads a credential.

## Template refresh

This worker ships cog templates (the helper scripts, `PUBLISHING.md`, `release-plz.toml`, and the
optional `dist-workspace.toml`), so it follows the shared refresh routine at
`$(cog skill-refs path bootstrap/template-refresh-routine.md)` on every run: check freshness, review
and update the shared template under `skill-refs/templates/cargo-publish/` when stale or missing, stamp
the review, then reconcile the target. The freshness type is `rust` (cargo-publish is Rust-only, one
template set):

```bash
cog bootstrap-template-review check --domain cargo-publish --type rust --json
```

When `review.fresh` is `true`, reuse the cached `summary` and skip the publishing-practice research —
go straight to deploying in the Workflow below. When it is `stale` or `missing`, web-research current
crates.io / release-plz / cargo-dist best practice, update `skill-refs/templates/cargo-publish/` when
justified, then stamp with `cog bootstrap-template-review stamp --domain cargo-publish --type rust ...`
— even when the conclusion is "no template change" — before reconciling.

## Workflow

1. Run `cog cargo-publish-detect --json`. Read `crate_kind`, `is_publishable`, `ci_provider`,
   `release_tool`, `semver_tool`, `ships_binaries`, `metadata`, and `cargo_runner`.

2. If there is no `Cargo.toml` (`crate_kind=none`), report that `bootstrap-rust` must scaffold the crate
   first and stop — this skill publishes an existing crate, it does not create one.

3. Read the `metadata` block and surface precise crates.io metadata gaps to `bootstrap-rust`:
   `has_description` and `has_license` are the required, publish-rejecting fields — crates.io hard-rejects
   a publish that lacks either; `has_repository`, `keywords_count`, and `categories_count` (canonical
   slugs, or the publish fails) are recommended for discovery. This skill surfaces the gaps to the
   metadata owner and never edits `Cargo.toml` itself.

4. Decide the **auth mode** from `$(cog skill-refs path rust/rust-publish-conventions.md)`: Trusted
   Publishing/OIDC when `ci_provider` is `github`/`gitlab`, else a local token via `cargo login`. The
   first publish is always manual, with a `publish-new`, exact-crate-scoped, shortest-expiry token that
   is revoked once OIDC is live.

5. Decide the **release tool**: `release-plz` by default when CI is present, `cargo-release` for an
   explicit local/no-bot preference.

6. Decide **binary distribution (cargo-dist)** — a first-class conditional step for CLI/app crates.
   Include it (`--with-dist`) when `ships_binaries.hint` is set and the operator confirms the crate
   ships prebuilt binaries. cargo-dist produces its own `.github/workflows/release.yml`
   (shell/PowerShell/Homebrew-tap installers; `cargo-binstall` then works from GitHub Releases) — a
   separate file from the release-plz workflow (`release-plz.yml`), so the crates.io Trusted Publisher
   keeps matching the actual release-plz filename. `cog cargo-publish-apply --with-dist` lays down
   `dist-workspace.toml` only; generating `release.yml` (`dist init` first time, `dist generate` after
   config edits) is a manual operator follow-up. Library-only crates never need it.

7. Note that the **SemVer gate** is load-bearing when `crate_kind=lib` (`cargo-semver-checks`, native in
   release-plz); a bin-only crate documents a policy but needs no API check.

8. Resolve the docs destination: `--doc-dir docs` when a `docs/` directory exists, else `--doc-dir .`
   to land `PUBLISHING.md` at the repo root.

9. Refresh the templates first (see **Template refresh**): `cog bootstrap-template-review check
   --domain cargo-publish --type rust --json`, update + stamp when stale/missing. Then run
   `cog cargo-publish-apply` with the chosen flags and conflict policy to deploy the scripts, runbook,
   and any selected config.

10. Run `cog cargo-publish-check --json` for go/no-go readiness and report the result. Review its
    `package_list` for non-build-input junk (`docs/`, `.github/`, `scripts/`, `release-plz.toml`,
    `dist-workspace.toml`, `justfile`, `flake.nix`, editor/lint configs) and surface a recommended
    `exclude` denylist to `bootstrap-rust` to keep the `.crate` lean; note the SPDX-`license` footgun
    (an `include` allowlist must list `README` and `LICENSE` explicitly, since neither is auto-included
    when `license` is an SPDX expression). `metadata.has_exclude`/`has_include` show whether trimming is
    already configured.

11. Surface fragments to their owners rather than writing those paths: publish/version recipes that
    invoke `scripts/publish-dry`/`scripts/publish`/`scripts/release` to the taskrunner domain, and the
    release CI requirements (release-plz job with `id-token: write` and no `CARGO_REGISTRY_TOKEN`, the
    manual first publish) to the CI domain — each `--type rust`. When `--with-dist` was chosen, note
    that cargo-dist's `.github/workflows/release.yml` is generated by the operator (`dist init` /
    `dist generate`) and stays a separate file from `release-plz.yml`. Hand the metadata gaps and the
    recommended `exclude` denylist to `bootstrap-rust`.

12. Present a summary: the auth mode, release tool, and cargo-dist decision (and, when cargo-dist was
    selected, the `dist init`/`dist generate` → `release.yml` follow-up); the deployed files; the
    readiness result; the metadata and tarball-hygiene gaps and the fragments handed to other domains;
    the first-publish-is-manual reminder; and next steps.

## Guardrails

- Deterministic mechanics stay behind `cog cargo-publish-detect`/`-check`/`-apply`; the only script-local
  shell is the deployed auth gate.
- Never read, echo, or inspect a credential; the dry-run path is never auth-gated; the first publish is
  manual; never run a real `cargo publish`.
- Surface fragments to their owners: crates.io metadata to `bootstrap-rust`, task recipes to the
  taskrunner domain, the release CI workflow to the CI domain — each `--type rust`.
- When cargo is unreachable, report it and stop; readiness needs a reachable cargo, not a token.
- Treat cargo-dist's generated `.github/workflows/release.yml` as an artifact: never hand-edit or
  template it, keep it a separate file from the release-plz workflow (`release-plz.yml`), and register
  only `release-plz.yml` with the crates.io Trusted Publisher; `cog` lays down `dist-workspace.toml`
  only and never runs `dist`.
- Do not run git commands unless the operator authorizes it.
