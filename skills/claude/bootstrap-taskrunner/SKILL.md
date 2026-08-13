---
name: bootstrap-taskrunner
description: >
  Scaffold the project's justfile with lint, test, build, fmt, and check
  recipes wired to the toolchain it actually has, running each through the
  devshell when the project has a flake. Use when the user says
  "bootstrap-taskrunner", "taskrunner", "justfile", "set up just", or
  "task runner".
model: opus
effort: low
---

<!-- trigger-tests: "bootstrap-taskrunner", "taskrunner", "justfile", "set up just", "task runner" -->

# Bootstrap task runner

Give the project a `justfile` whose `lint`, `test`, `build`, `fmt`, and `check` recipes run the commands the project's real toolchain provides. `just` is the only task runner (ADR-0028): a project that ships some other build file keeps it as its own build system, and a justfile lands beside it.

A recipe is worth generating only when a signal backs it. A recipe with nothing behind it is a documented placeholder, not a guess.

Follow the shared routine at `$(cog skill-refs path bootstrap/domain-worker-routine.md)`:

```bash
cog bootstrap-template-review check --domain taskrunner --type just --json
```

A fresh review means reuse the cached `summary` and go straight to tailoring; stale or missing means research current `just` recipe conventions for the detected toolchain, update `skill-refs/templates/taskrunner/just/` when justified, and `stamp` before reconciling.

## Detect

```bash
cog taskrunner-detect --json
```

`type` is always `just`. The value is in `signals[]`, which names the build conventions actually present — `cargo (Cargo.toml)`, `npm (package.json)`, `poetry (poetry.lock)`, `python (pyproject.toml)`, `go (go.mod)`, `zig (build.zig)`, `nix flake (flake.nix)` — and those are what decide which recipes to write.

## Deploy

```bash
cog taskrunner-apply [--append] --conflict "$POLICY" --json
```

Without `--append` it copies the template `justfile` to the project root under the conflict policy. With `--append` it augments an existing justfile in place: only the standard recipes the file is missing, inside a managed `# --- cog taskrunner ---` block, preserving every recipe the project already defines. `--append` is idempotent and copies the full template fresh when no justfile exists.

Reach for `--append` whenever a justfile is already present. Reconciling a hand-written runner is judgment — read what is there before deciding — and a wholesale overwrite needs the operator's word.

## Tailor

Back each recipe with the tool a signal named: `cargo build` / `cargo test` / `cargo clippy` for a Cargo project, `npm run` / `npm test` for Node, `poetry run` for Poetry. Where the brief carries publishing recipe fragments, or the project ships `scripts/publish`, `scripts/publish-dry`, or `scripts/release`, back `publish`, `publish-dry`, and `release` recipes on those.

When a `flake.nix` is present, wire every recipe through the devshell so tasks run in the pinned environment — prefix the command with `nix develop --command`, e.g. `nix develop --command cargo test`.

Report the runner deployed or augmented, each recipe with the tool behind it, any recipe left as a placeholder, and `just --list` as the way to see them.
