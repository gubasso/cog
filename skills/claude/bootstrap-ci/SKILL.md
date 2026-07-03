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
   conventional toolchain for the language and call the task runner directly.

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
