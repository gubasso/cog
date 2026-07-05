---
name: bootstrap-ci
description: >
  Sets up a CI workflow for the current project, delegating deterministic git
  remote detection and template copying to the cog CLI while keeping CI target
  choice, flake reuse, and web research judgment in prose. Use when the user
  says "ci workflow", "set up ci", "github actions", or "gitlab ci".
model: opus
effort: low
---

<!-- trigger-tests: "ci workflow", "set up ci", "github actions", "gitlab ci" -->

# Bootstrap CI Skill

Deploy a tailored CI pipeline for the current project. The target host comes from the project's own
git remote, and the jobs reuse the project's Nix devshell so CI runs the same toolchain as local
development.

Principle: templates are broad and general; the deployed pipeline is precise and wired to the
project's actual task runner and toolchain.

## Inputs

- Template directory: cog's `skill-refs/templates/ci/` tree, or a caller-supplied `--template-root`.
- Current working directory: the target project.

## Cog Contract

`cog` must be installed and on `PATH`; a bare call fails legibly if it is missing. Detect the CI
target from the project's git remote:

```bash
cog ci-detect --json
```

`ci-detect` reads `<project>/.git/config` as an INI file (it never invokes `git`), classifies the
`origin` remote host, and emits:

```json
{
  "ok": true,
  "project_root": "/repo",
  "remote_url": "https://github.com/owner/repo.git",
  "host": "github",
  "target": "github",
  "requires_question": false,
  "existing_ci": [],
  "reason": null
}
```

`host` is `github`, `gitlab`, `other`, or `none` (no origin remote). `target` is `github` or
`gitlab` when the host maps to a supported provider, otherwise `none`. When `target` is `none` and
`requires_question` is `true`, ask the operator which CI target to use before deploying. Deploy the
matching template after conflict policy is explicit:

```bash
cog ci-apply --target "$TARGET" --conflict "$CONFLICT_POLICY" --json
```

`ci-apply` copies the target's files (GitHub nests `ci.yml` under `.github/workflows/`; GitLab writes
`.gitlab-ci.yml` at the project root) and emits
`{ok, target, template_dir, copied[], skipped[], conflicts[], conflict, reason}`. Its `--conflict`
policy is `overwrite`, `skip`, or `abort` (default `abort`). Reconciling a pre-existing CI file is
judgment that stays in this skill: inspect the existing pipeline and merge in prose rather than
blind-overwriting a config the project already tuned.

## Template refresh

Follow the shared refresh routine at `$(cog skill-refs path bootstrap/template-refresh-routine.md)` on
every run: check freshness, review and update the shared template when stale or missing, stamp the
review, then reconcile the target — installing when absent, applying improvements when present. The
freshness type is the resolved CI target (`github` or `gitlab`). Use the freshness `check` JSON
`/bootstrap` supplied in the brief; when it is absent, resolve the target with `ci-detect` and run it
yourself:

```bash
cog bootstrap-template-review check --domain ci --type "$TARGET" --json
```

When `review.fresh` is `true`, reuse the cached `summary` and skip the CI research — go straight to
wiring the jobs in the Workflow below. When it is `stale` or `missing`, web-search current CI practice
for the host (step 4), update `skill-refs/templates/ci/<target>/` when justified, then stamp the review
with `cog bootstrap-template-review stamp --domain ci --type "$TARGET" ...` — even when the conclusion is
"no template change" — before reconciling the CI files. Reuse the flake via `nix develop --command`
whenever a `flake.nix` exists. `stamp` fails fast when the template SoT is not writable; surface that.

## Workflow

1. Run `cog ci-detect --json` to resolve the target from the git remote.

2. If `requires_question` is `true` (`target == none`), ask the operator which CI target to use
   (`github` or `gitlab`). Do not guess a provider without evidence from the remote.

3. If `existing_ci` lists a pipeline, decide whether to reconcile or replace it, and set the conflict
   policy accordingly. Ask before overwriting a config the project already tuned.

4. Web-search current CI practice for the detected host as enhancers: confirm current action or
   image versions and recommended job structure. These are optional; proceed from the cog template
   and this prose when offline.

5. Deploy the matching template with `cog ci-apply --target "$TARGET"`.

6. Wire the jobs to the project's toolchain. When a `flake.nix` is present, run each task through the
   devshell — `nix develop --command <task>` — referencing the task runner's recipe names (for a
   justfile, `just lint`, `just test`, `just build`). When no flake is present, set up the
   conventional toolchain for the language and call the task runner directly. Flake reuse is a verified
   postcondition: when reconciling a pre-existing pipeline that predates the flake, add the
   `nix develop` wrapping rather than leaving CI on a divergent toolchain. When the brief carries
   publishing or release workflow requirements, add the release job they describe (for a release-plz
   crate: `permissions: id-token: write` and no `CARGO_REGISTRY_TOKEN`, the first publish stays manual,
   and an optional binary-distribution job), reconciled under the conflict policy.

7. Present a final summary: the target deployed, the jobs wired to the flake or conventional
   toolchain, the task names each job runs, and any pre-existing pipeline reconciled.

## Guardrails

- Target the actual remote provider; ask the operator when the remote is absent or unsupported.
- Reuse the project's Nix devshell for CI jobs whenever a `flake.nix` is present, so CI and local
  development share one toolchain.
- Reconcile a pre-existing CI pipeline in prose; ask before overwriting settings the project already
  tuned.
- Treat helper output as mechanics only. CI target choice, job wiring, and web-search enrichment
  remain skill judgment.
