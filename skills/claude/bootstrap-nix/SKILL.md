---
name: bootstrap-nix
description: >
  Scaffold a per-project Nix devShell for the current project: a minimal
  flake.nix built from detected dependencies, an .envrc that direnv auto-loads,
  interactive and non-interactive shell access, and CI steps that reuse the
  same flake. Delegates deterministic type detection and template copying to the
  cog CLI while keeping flake tuning and reconciliation judgment in prose. Use
  when the user says "bootstrap-nix", "set up nix", "nix devshell", "add a
  flake", or "nix develop".
model: opus
effort: low
---

<!-- trigger-tests: "bootstrap-nix", "set up nix", "nix devshell", "add a flake", "nix develop" -->

# Bootstrap Nix Skill

Give the current project a reproducible per-project development environment: a `flake.nix` that pins
its toolchain, an `.envrc` that direnv loads automatically, and CI that reuses the same flake.
Dependency resolution stays with the project's own package manager (Poetry, npm, cargo); Nix owns the
toolchain and system tools.

Principle: templates are broad starting points; the deployed `flake.nix` is tuned precisely to the
project's actual detected dependencies — add only what the project needs.

## Inputs

- `$ARGUMENTS`: optional template type — `python`, `rust`, `node`, `zig`, or `generic`.
- The cog nix template domain (`templates/nix/<type>`), or a caller-supplied `--template-root`.
- Current working directory: the target project.

## Cog Contract

`cog` must be installed and on `PATH`; a bare call fails legibly if it is missing. Detect the template
type when the user did not provide one:

```bash
cog nix-devshell-detect --json
```

Detection classifies the project's language signals and maps a single recognized signal to
`python|rust|node|zig`. A project with no recognized signal, or with ambiguous signals, resolves to
`generic` with `ok:true` — nix detection always yields a usable target and never hard-fails. Pass an
explicit type to override:

```bash
cog nix-devshell-detect --type "$TYPE" --json
```

The detection helper emits `{ok, project_root, template_root, requested_type, detected_type,
confidence, classification, signals, conflicts, template_dir, template_config, template_exists,
reason}`. `detected_type` is the template directory; `confidence` is `high` (single signal),
`requested` (explicit `--type`), or `fallback` (generic).

Deploy the template after conflict policy is explicit, per file:

```bash
cog nix-devshell-apply \
  --type "$TYPE" \
  --flake-conflict "$FLAKE_POLICY" \
  --envrc-conflict "$ENVRC_POLICY" \
  --companion-conflict "$COMPANION_POLICY" \
  --json
```

The apply helper copies `flake.nix` and `.envrc`, plus `rust-toolchain.toml` for the `rust` type
(the companion). Each destination has its own policy (`overwrite`, `skip`, or `abort`, default
`abort`) and is guarded to stay inside the project root. It emits `{ok, project_root, template_root,
type, template_dir, copied[], skipped[], conflicts[], flake_conflict, envrc_conflict,
companion_conflict, reason}`. The helper never runs `nix flake lock`, edits `.gitignore`, or touches
`flake.lock`.

Reconciling a pre-existing `flake.nix` or `.envrc` is judgment: inspect both files, decide the merge
in prose, and use the helper only for safe copies. Never blind-overwrite an existing flake or envrc.

## Workflow

1. Resolve the type. If `$ARGUMENTS` gives one, run `nix-devshell-detect --type "$TYPE"` to validate
   the template path. Otherwise run `nix-devshell-detect --json` and take `detected_type` (which is
   `generic` when nothing specific is recognized).

2. Analyze the project: manifests (`pyproject.toml`, `Cargo.toml`, `package.json`, `build.zig`), the
   runtime version it targets, native/system libraries it links, and any existing `flake.nix` /
   `.envrc`.

3. Deploy the template. Choose per-file conflict policies from the analysis; when a file already
   exists, reconcile it in prose rather than overwriting blindly, then apply only the safe copies:

   ```bash
   cog nix-devshell-apply --type "$TYPE" \
     --flake-conflict "$FLAKE_POLICY" --envrc-conflict "$ENVRC_POLICY" \
     --companion-conflict "$COMPANION_POLICY" --json
   ```

4. Tune `flake.nix` minimally to the detected dependencies:
   - add only the `packages` / `buildInputs` the project actually needs (its runtime, package
     manager, and any `-sys`/native system libraries such as `openssl`, `pkg-config`, `zlib`);
   - Python: pin the interpreter as the single source of truth and keep the
     `assert python.version == pkgs.poetry.python.version` guard so the venv cannot drift from the
     pin; keep the `LD_LIBRARY_PATH` line that exposes `libstdc++.so.6`/`libz.so.1` for manylinux
     wheels;
   - Rust: leave the version declaration in `rust-toolchain.toml` — the flake reads it via
     `fromRustupToolchainFile`; add `-sys` native deps to `buildInputs`/`nativeBuildInputs` as needed;
   - keep the flake lean: remove template packages the project does not use.

5. Establish auto-load. The `.envrc` is `use flake` (Python also layers the Poetry venv onto `PATH`).
   Interactive shells enter the devShell after a one-time `direnv allow` on `cd`. Non-interactive
   contexts (CI, agents, editor task runners, `bash -c`) need explicit activation — the prompt hook
   does not fire there. Wrap commands with `direnv exec . <cmd>` or `nix develop --command <cmd>`. See
   `cog skill-refs path nix/non-interactive-direnv.md`.

6. Generate CI steps that reuse the flake — run each task through `nix develop --command <task>` so CI
   uses the same pinned toolchain as the shell. Hand these steps to the CI scaffolding contract rather
   than writing CI files here.

7. Ensure `.gitignore` carries `.direnv/` and `/result`. The gitignore domain owns the `.gitignore`
   path; surface the required ignore fragments to it rather than editing `.gitignore` here. The nix
   fragment has a dedicated, type-independent, idempotent top-up that guarantees both lines land even
   when the `.gitignore` deliverable already exists:

   ```bash
   cog gitignore-apply --type nix --append --json
   ```

8. Present a summary: the deployed type, flake packages added or removed, the runtime pin, how to
   enter the shell (`direnv allow` / `nix develop`), the non-interactive command form, and next steps:

   ```bash
   nix flake lock        # on a host with nix + network; commit the generated flake.lock
   direnv allow          # trust the .envrc once for interactive cd
   ```

## Guardrails

- Never fabricate `flake.lock`; it is generated only on a host with `nix` and network access
  (`nix flake lock`) and then committed.
- Keep the flake minimal and reproducible: pin inputs, add only necessary packages, and do not turn a
  devShell into a full build system unless the project asks for it.
- Reconcile an existing `flake.nix` / `.envrc` in prose; ask before any destructive overwrite.
- Leave `.gitignore` writes to the gitignore domain; leave CI file writes to the CI scaffolding.
- Web-research current flake, `nix develop`, and nix-direnv practice as optional enhancers; the cog
  templates and this prose are sufficient on their own.
