---
name: bootstrap-taskrunner
description: >
  Delegates deterministic task-runner detection and template copying to the
  cog CLI while preserving recipe selection, toolchain wiring, and conflict
  decisions in prose. Scaffolds a justfile by default and augments an existing
  Makefile in place. Use when the user says "taskrunner", "justfile", "set up
  just", or "task runner".
model: opus
effort: low
---

<!-- trigger-tests: "taskrunner", "justfile", "set up just", "task runner" -->

# Bootstrap Task-runner Skill

Scaffold a project task runner with `lint`, `test`, `build`, `fmt`, and `check` recipes tailored to
the project's actual toolchain.

Principle: `just` is the default runner; a project that already ships a `Makefile` keeps `make`, and
its `Makefile` is augmented in place rather than replaced.

## Inputs

- `$ARGUMENTS`: optional runner type, `just` or `make`.
- Template directory: cog's `skill-refs/templates/taskrunner/` tree, or a caller-supplied
  `--template-root`.
- Current working directory: the target project.

## Cog Contract

`cog` must be installed and on `PATH`; a bare call fails legibly if it is missing. Detect the runner
type and the project's build conventions:

```bash
cog taskrunner-detect --json
```

The detector is deterministic: it returns `make` when a `Makefile`, `makefile`, or `GNUmakefile`
already exists at the project root, and `just` otherwise. Its `signals[]` surface detected
lint/test/build conventions (`cargo`, `npm`, `poetry`, `go`, `zig`, `nix flake`) that inform which
recipes are worth generating. It emits:

```json
{
  "ok": true,
  "project_root": "/repo",
  "type": "just",
  "signals": ["cargo (Cargo.toml)"],
  "reason": null
}
```

Apply the selected type's template with an explicit conflict policy:

```bash
cog taskrunner-apply --type "$TYPE" --conflict "$POLICY" --json
```

`taskrunner-apply` copies one file — `justfile` for `just`, `Makefile` for `make` — to the project
root and emits `{ok, type, mode, copied[], skipped[], conflicts[], appended[], conflict, reason}`. Its
`--conflict` policy is `overwrite`, `skip`, or `abort` (default `abort`). A pre-existing `Makefile`
is preserved under `skip`/`abort`; reconciling it stays this skill's judgment.

`--append` augments an existing runner in place: it injects only the standard
`lint`/`test`/`build`/`fmt`/`check` targets the file is missing, inside a managed block, and preserves
every target the project already defines. It is idempotent (a re-run adds nothing) and copies the full
template fresh when the file is absent:

```bash
cog taskrunner-apply --type "$TYPE" --append --json
```

## Template refresh

Follow the shared refresh routine at `$(cog skill-refs path bootstrap/template-refresh-routine.md)` on
every run: check freshness, review and update the shared template when stale or missing, stamp the
review, then reconcile the target — installing when absent, augmenting when present. Use the freshness
`check` JSON `/bootstrap` supplied in the brief; when it is absent, resolve the runner type with
`taskrunner-detect` and run it yourself:

```bash
cog bootstrap-template-review check --domain taskrunner --type "$TYPE" --json
```

When `review.fresh` is `true`, reuse the cached `summary` and skip the research — go straight to
tailoring recipes in the Workflow below. When it is `stale` or `missing`, review current `just`/`make`
recipe conventions for the detected toolchain, update `skill-refs/templates/taskrunner/<type>/` when
justified, then stamp the review with `cog bootstrap-template-review stamp --domain taskrunner --type
"$TYPE" ...` — even when the conclusion is "no template change" — before reconciling. Reconcile an
existing runner through `--append` where possible, never a wholesale overwrite. `stamp` fails fast when
the template SoT is not writable; surface that.

## Workflow

1. Run `cog taskrunner-detect --json` to resolve the runner type and read the build-tool signals.
   Honor an explicit `$ARGUMENTS` type over the default.

2. For a fresh project (no `Makefile`), deploy the `justfile` with
   `cog taskrunner-apply --type just --conflict abort --json`.

3. For a project that already ships a `Makefile`, keep `make`. Inject the missing standard targets
   deterministically with `cog taskrunner-apply --type make --append --json`, which preserves every
   existing target and is idempotent. Then tailor the injected placeholders in prose. Never overwrite
   the file.

4. Tailor recipes to the detected toolchain. Generate a recipe only when a signal backs it — for
   example `cargo build`/`cargo test`/`cargo clippy` for a Cargo project, `npm run`/`npm test` for a
   Node project, `poetry run` for a Poetry project. Leave a recipe as a documented placeholder when no
   tool backs it yet. When the brief carries publishing recipe fragments, or the project ships
   `scripts/publish`/`scripts/publish-dry`/`scripts/release` helpers, back `publish`/`publish-dry`/`release`
   recipes on those.

5. When a `flake.nix` is present, wire each recipe through the devshell so tasks run in the pinned
   environment: prefix the command with `nix develop --command`, e.g. `nix develop --command cargo
   test`.

6. Present a final summary: the runner deployed or augmented, the recipes generated and their backing
   tools, any recipes left as placeholders, and the command to list tasks (`just --list` or
   `make help`).

## Guardrails

- Default to `just`; choose `make` only when a `Makefile` already exists.
- Augment an existing `Makefile`, never overwrite it. Ask before any destructive change.
- Treat helper output as mechanics only. Recipe selection, toolchain wiring, and Makefile
  reconciliation remain skill judgment.
