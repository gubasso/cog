---
name: bootstrap-ci
description: >
  Deploy a CI pipeline targeting the project's actual git remote, with every
  job running through the project's Nix devshell so CI and local development
  share one toolchain. Use when the user says "bootstrap-ci", "ci workflow",
  "set up ci", "github actions", or "gitlab ci".
model: opus
effort: low
---

<!-- trigger-tests: "bootstrap-ci", "ci workflow", "set up ci", "github actions", "gitlab ci" -->

# Bootstrap CI

Deploy a CI pipeline for the project. The target host comes from the project's own git remote, never a guess, and the jobs run through the project's Nix devshell so CI uses the same toolchain as local development. The template is broad; the deployed pipeline names this project's real recipes.

Follow the shared routine at `$(cog skill-refs path bootstrap/domain-worker-routine.md)`; the freshness type is the resolved target:

```bash
cog bootstrap-template-review check --domain ci --type "$TARGET" --json
```

A fresh review means reuse the cached `summary` and go straight to wiring the jobs; stale or missing means research current CI practice for the host — current action or image versions, recommended job structure — update `skill-refs/templates/ci/<target>/` when justified, and `stamp` before reconciling.

## Resolve the target

```bash
cog ci-detect --json
```

`ci-detect` reads `<project>/.git/config` as an INI file — it never invokes `git`. `host` is `github`, `gitlab`, `other`, or `none`; `target` is `github` or `gitlab` when the host maps to a supported provider, otherwise `none`.

When `requires_question` is `true` (`target` is `none`), ask the operator which target to use. Do not guess a provider without evidence from the remote. When `existing_ci` lists a pipeline, decide whether to reconcile or replace it and set the conflict policy accordingly — reconciling a tuned pipeline is judgment, done by reading it, and overwriting one needs the operator's word.

```bash
cog ci-apply --target "$TARGET" --conflict "$POLICY" --json
```

GitHub nests `ci.yml` under `.github/workflows/`; GitLab writes `.gitlab-ci.yml` at the project root.

## Wire the jobs

**Flake reuse is a verified postcondition.** When a `flake.nix` is present, run every task through the devshell — `nix develop --command <task>` — naming the justfile's own recipes (`just lint`, `just test`, `just build`). When reconciling a pipeline that predates the flake, add the `nix develop` wrapping rather than leaving CI on a divergent toolchain. With no flake, set up the conventional toolchain for the language and call the task runner directly.

When the brief carries release requirements, pick the tooling by ecosystem from `$(cog skill-refs path release/release-workflow-conventions.md)`:

- **No-registry projects** (Bash and similar): the committed `VERSION` is the version source of truth, bumped in place by git-cliff, and the annotated `v*` tag mirrors it. Deploy the git-cliff + tag-triggered release core with `cog ci-apply --with-release` (adds `release.yml`, `cliff.toml`, and a committed `VERSION`), then wire `release.yml` to the flake and task runner like every other job.
- **release-plz crates:** keep the release-plz job shape — `permissions: id-token: write`, no `CARGO_REGISTRY_TOKEN`, first publish manual, optional binary-distribution job.

Reconcile every release file under the conflict policy.

Report the target deployed, the jobs wired to the flake or conventional toolchain, the task names each job runs, and any pre-existing pipeline reconciled.
