---
name: bootstrap-repo
description: >
  Establish a repository's baseline files: a language-aware .gitignore, an SPDX
  LICENSE with the holder and year confirmed by the operator, and a README
  skeleton tailored to the actual project. Use when the user says
  "bootstrap-repo", "repo starter", "gitignore", "license", or "readme scaffold".
model: opus
effort: low
argument-hint: "[python|rust|node|zig|c|bash|generic]"
---

<!-- trigger-tests: "bootstrap-repo", "repo starter", "gitignore", "license", "readme scaffold" -->

# Bootstrap repo baseline

Establish the three files every repository needs before anything else: a language-aware `.gitignore`, an SPDX `LICENSE`, and a `README.md` skeleton. Templates are broad; the deployed files are precise — repo-specific detail is decided with the operator and written into them.

This skill is the **single writer of `.gitignore`** for a run. Ignore fragments other domains need arrive through the brief and are appended here.

Follow the shared routine at `$(cog skill-refs path bootstrap/domain-worker-routine.md)`; the freshness type is the gitignore type:

```bash
cog bootstrap-template-review check --domain repo --type "$TYPE" --json
```

`check` reports the `gitignore`, `license`, and `readme` template roots in `template_roots[]`. A fresh review means reuse the cached `summary`; stale or missing means research current ignore patterns and README conventions for the stack, update the relevant `skill-refs/templates/{gitignore,license,readme}/` trees when justified, and `stamp` before reconciling. The operator-confirmed SPDX id, holder, and year survive any refresh — a license is never defaulted.

## .gitignore

```bash
cog gitignore-detect [--type "$TYPE"] --json
cog gitignore-apply --type "$TYPE" --conflict "$POLICY" --json   # fresh file
cog gitignore-apply --type "$TYPE" --append --json               # existing file
```

Detection always resolves; an unrecognized or ambiguous project falls back to `generic`.

Use `--append` whenever a `.gitignore` already exists: it adds only the missing lines, inside a managed block, and is idempotent. Every template already carries the nix devshell lines `.direnv/` and `/result`; confirm both are present when reconciling.

## LICENSE

Confirm the license with the operator before deploying — present the shipped ids and ask for the SPDX id and year directly. Seed the copyright holder from the repository's own git identity via `$(cog skill-refs path bootstrap/git-identity-preflight.md)`: read `cog git-identity check --json` and offer its `name` as the default for the operator to confirm, pausing with the step-by-step it describes when identity is unset.

```bash
cog license-apply --list --json
cog license-apply --spdx "$SPDX" --holder "$HOLDER" --year "$YEAR" --conflict "$POLICY" --json
```

cog substitutes `{{YEAR}}` and `{{HOLDER}}` for the licenses carrying a copyright line (MIT, BSD-3-Clause), which therefore require `--holder` and `--year`; Apache-2.0 and GPL-3.0 ship verbatim. An unknown `--spdx` fails legibly. Reconcile a pre-existing license with the operator rather than overwriting it.

A dual license is two applies under two names, via `--filename`:

```bash
cog license-apply --spdx mit --holder "$HOLDER" --year "$YEAR" --filename LICENSE-MIT --json
cog license-apply --spdx apache-2.0 --filename LICENSE-APACHE --json
```

`--filename` accepts only conventional license basenames (`LICENSE`, `LICENSE-<id>`, `COPYING`, and their `.md`/`.txt` forms), which is the same set `cog bootstrap-audit` resolves the license deliverable from — so a dual layout reports present rather than sending the operator back for an SPDX id they already gave. `MIT OR Apache-2.0` is the Rust ecosystem's default; record the choice in the crate's `license` field too.

## README

```bash
cog readme-apply --conflict "$POLICY" --json
```

Then tailor it from the actual project: the title, description, install steps, devshell entry, task commands, and license section. Reconcile a pre-existing README in prose rather than overwriting it.

Report the `.gitignore` type and any appended fragments, the deployed license with its holder and year, and the README sections established or tailored.
