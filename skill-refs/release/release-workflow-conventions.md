# Release & versioning conventions (the way we intend)

The source of truth for how the bootstrap workers set up a project's release workflow and versioning.
It covers the version source-of-truth model, the release tool to pick per ecosystem, and the
distribution fan-out for projects with no package registry. The crate-specific publish judgment
(auth, semver gating, tarball hygiene) lives in `rust/rust-publish-conventions.md`; this reference is
the general model that Rust one specializes.

## Version source of truth

**The committed version-in-repo is the source of truth; the annotated `vX.Y.Z` tag is derived from it
and mirrors it.** Two roles, kept distinct:

- **Authoring SoT** — the version field or file that lives in the repository and is bumped in place
  from Conventional Commits. This is where the number is decided and reviewed.
- **Published record** — the annotated tag cut to match the committed version. It is the immutable
  marker every distribution channel keys off (registries, `install.sh`, AUR, OBS `@PARENT_TAG@`).

Keep the number authored in exactly one committed place per project; everything downstream derives
from it. There is no second hand-maintained copy to drift, and nothing is left uncommitted or
generated at build time.

The authoring SoT per ecosystem:

| Ecosystem   | Committed version SoT              | In-place bump tool                    |
| ----------- | ---------------------------------- | ------------------------------------- |
| Rust        | `Cargo.toml` `[package] version`   | `release-plz`                         |
| Node        | `package.json` `version`           | Changesets                            |
| Python      | `pyproject.toml` / `__version__`   | release-please or python-semantic-release |
| Bash / none | `VERSION` (one line, repo root)    | `git-cliff` (`--bump`)                |
| Cross-lang  | each ecosystem's manifest          | release-please                        |

The release tool bumps the committed version and writes the changelog from Conventional Commits, then
the tag is cut to match — by the bot on merge (release-plz, Changesets, release-please) or by the
maintainer in the release ritual (git-cliff). Either way the committed version leads and the tag
mirrors it.

## Match the tool to the committed version file

Pick a release tool that maintains that ecosystem's committed version **in place**. A tool whose
updater cannot deterministically bump the committed file is the wrong tool, even if it runs.

**release-please is disqualified for a plain `VERSION` file (Bash / no-registry projects).** Its
`simple` release-type natively updates only a file literally named `version.txt` (whole-file replace);
any other file goes through the generic `extra-files` updater, which rewrites **only** lines carrying
an `x-release-please-version` marker comment. A clean bare `VERSION` has no marker, so the updater
silently no-ops and `VERSION` drifts stale forever while the tag advances. release-please also couples
to GitHub PRs/labels and does nothing for `install.sh`/AUR/OBS distribution. For a Bash CLI, use
`git-cliff` — it writes the committed `VERSION` deterministically and reads git history for the
changelog with no registry or forge coupling.

## Bash / no-registry release path

For a pure-Bash (or other no-central-registry) project, **tagging is publishing**: one signed `v*`
tag fans out to a `curl | bash` installer, AUR, and OBS-hosted `.rpm`/`.deb` repos. The core files:

- `VERSION` — one line (`0.1.0`), committed, the authoring SoT. The `version` subcommand reads it
  (shipped alongside the lib, or placeholder-substituted at install), with
  `git describe --tags --dirty --always` as the dev-checkout fallback.
- `cliff.toml` — git-cliff config (Keep-a-Changelog preset) that computes the next version and writes
  `CHANGELOG.md`.
- `.github/workflows/release.yml` — triggered on a `v*` tag: test → build the dist tarball →
  git-cliff release notes → `gh release create`, plus any downstream distribution trigger.

Release ritual: `git-cliff --bump` writes `VERSION` + `CHANGELOG.md`, commit, cut the signed
annotated tag to match, push `--follow-tags`; CI takes it from the tag.

## Trusted publishing and CI auth

For ecosystems that publish to a registry, default to Trusted Publishing (OIDC) from CI over
long-lived token secrets, and keep the first publish manual. The Rust specifics (release-plz OIDC job
shape, `id-token: write`, no `CARGO_REGISTRY_TOKEN`, semver gating) live in
`rust/rust-publish-conventions.md`.

## Workflow file naming (publish vs binary distribution)

When a project runs both a **registry-publish** workflow and a separate **binary-distribution**
generator, keep them in **separate workflow files** and register only the *publish* file with the
registry's trusted publisher (which matches on the workflow filename). For Rust: the publish workflow
is `release-plz.yml` (the trusted-publisher filename) and cargo-dist's binary-build workflow is
`release.yml` — its own default, kept distinct so the two never collide. A no-registry project (Bash)
has a single tag-triggered `release.yml` and no trusted publisher, so no collision arises.

## External references (optional enhancers)

git-cliff, Conventional Commits, Keep a Changelog, SemVer, release-plz.dev, Changesets, release-please,
and the GNU coding standards for the `VERSION` file convention. The conventions above are
self-contained; the external links only enrich them.
