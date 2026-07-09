---
name: bootstrap-repo
description: >
  Scaffolds a repository's baseline files - a language-aware .gitignore, an
  SPDX LICENSE, and a README skeleton - delegating deterministic detection,
  template copying, and license substitution to the cog CLI while keeping
  tailoring and license judgment in prose. Use when the user says "repo
  starter", "gitignore", "license", or "readme scaffold".
model: opus
effort: low
---

<!-- trigger-tests: "repo starter", "gitignore", "license", "readme scaffold" -->

# Bootstrap Repo Skill

Establish a project's baseline repository files: a language-aware `.gitignore`, an SPDX `LICENSE`, and
a `README.md` skeleton. Deterministic detection, copying, and license substitution run through cog;
per-project tailoring and the license choice stay judgment.

Principle: templates are broad and general; the project files are precise and tailored — repo-specific
detail belongs in the deployed files, decided with the operator.

## Inputs

- `$ARGUMENTS`: optional project type for `.gitignore`, such as `python`, `rust`, `node`, `zig`, `c`,
  `bash`, or `generic`.
- Template trees: cog's `skill-refs/templates/gitignore/`, `skill-refs/templates/license/`, and
  `skill-refs/templates/readme/`, or a caller-supplied `--template-root`.
- Current working directory: the target project.
- License facts: the SPDX id, copyright holder, and year — always confirmed with the operator; the
  holder default comes from the repository's git identity.

## Cog Contract

`cog` must be installed and on `PATH`; a bare call fails legibly if it is missing.

Detect the `.gitignore` type when the operator did not provide one. Detection always resolves — an
unrecognized or ambiguous project falls back to `generic`:

```bash
cog gitignore-detect --json
```

Deploy `.gitignore` as the single writer of that path. Copy a fresh file under an explicit conflict
policy, or add missing ignore fragments to an existing file with marker-safe append:

```bash
cog gitignore-apply --type "$TYPE" --conflict "$POLICY" --json
cog gitignore-apply --type "$TYPE" --append --json
```

Every `.gitignore` template already carries the nix devshell lines `.direnv/` and `/result`; the
append mode adds only lines missing from the existing file, inside a managed block, and is idempotent.

List the shipped SPDX ids, then deploy the chosen `LICENSE`. cog substitutes `{{YEAR}}` and
`{{HOLDER}}` deterministically for the licenses that carry a copyright line (MIT, BSD-3-Clause);
Apache-2.0 and GPL-3.0 ship verbatim:

```bash
cog license-apply --list --json
cog license-apply --spdx "$SPDX" --holder "$HOLDER" --year "$YEAR" --conflict "$POLICY" --json
```

An unknown `--spdx` fails legibly; MIT and BSD-3-Clause require `--holder` and `--year`.

Deploy the `README.md` skeleton under an explicit conflict policy:

```bash
cog readme-apply --conflict "$POLICY" --json
```

Each helper emits `{ok, ...}` with `copied`, `skipped`, and `conflicts` arrays (gitignore adds
`mode` and `appended`; license adds `spdx`); treat that output as mechanics only.

## Template refresh

Follow the shared refresh routine at `$(cog skill-refs path bootstrap/template-refresh-routine.md)` on
every run: check freshness, review and update the shared templates when stale or missing, stamp the
review, then reconcile the target — installing when absent, applying improvements when present. The
freshness type is the gitignore type. Use the freshness `check` JSON `/bootstrap` supplied in the brief;
when it is absent, resolve the type with `gitignore-detect` and run it yourself:

```bash
cog bootstrap-template-review check --domain repo --type "$TYPE" --json
```

`check` reports the `gitignore`, `license`, and `readme` template roots in `template_roots[]`. When
`review.fresh` is `true`, reuse the cached `summary` and skip the research — go straight to reconcile in
the Workflow below. When it is `stale` or `missing`, web-research current ignore patterns and README
conventions for the stack (step 6), update the relevant `skill-refs/templates/{gitignore,license,readme}/`
trees when justified, then stamp the review with `cog bootstrap-template-review stamp --domain repo
--type "$TYPE" ...` — even when the conclusion is "no template change" — before reconciling `.gitignore`,
`LICENSE`, and `README.md`. Preserve the operator-confirmed SPDX id, holder, and year; never default a
license. `stamp` fails fast when the template SoT is not writable; surface that.

## Workflow

1. Resolve the `.gitignore` type. If `$ARGUMENTS` provides a type, validate it with
   `gitignore-detect --type "$TYPE"`; otherwise run `gitignore-detect --json` and use the detected or
   `generic` fallback type.

2. Deploy `.gitignore` as its single writer. For a new project, copy under an explicit conflict
   policy. For an existing `.gitignore`, use append mode to add missing fragments without clobbering,
   and confirm `.direnv/` and `/result` are present.

3. Confirm the license with the operator: present the shipped ids from `license-apply --list` and ask
   for the SPDX id and year directly — never default the SPDX id. Seed the copyright holder from the
   repository's git identity via the git-identity preflight
   (`$(cog skill-refs path bootstrap/git-identity-preflight.md)`): read `cog git-identity check --json`
   and offer its `name` as the default holder for the operator to confirm; when identity is unset, pause
   with the step-by-step it describes before asking for the holder.

4. Deploy the `LICENSE` with `cog license-apply`, passing `--holder` and `--year` for MIT and
   BSD-3-Clause. Reconcile a pre-existing `LICENSE` with the operator before overwriting.

5. Deploy the `README.md` skeleton with `cog readme-apply`, then tailor it: fill the title,
   description, install steps, dev-shell entry, task commands, and license section from the actual
   project. Reconcile a pre-existing README in prose rather than overwriting it.

6. Web-research current ignore patterns and README conventions for the detected stack as enhancers,
   and fold worthwhile additions into the deployed files.

7. Present a final summary: the `.gitignore` type and any appended fragments, the deployed license
   and its holder/year, and the README sections established or tailored.

## Guardrails

- Own `.gitignore` as the single writer of that path; use append mode to preserve an existing file.
- Confirm the SPDX id, holder, and year with the operator before deploying a `LICENSE`.
- Reconcile a pre-existing `LICENSE` or `README.md` with the operator rather than overwriting it
  silently.
- Treat helper output as mechanics only. Type selection, license choice, and tailoring remain
  judgment.
