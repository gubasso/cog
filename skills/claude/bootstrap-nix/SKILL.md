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

Give the current project a reproducible per-project development environment: a `flake.nix` that pins its toolchain, an `.envrc` that direnv loads automatically, and CI that reuses the same flake. Dependency resolution stays with the project's own package manager (Poetry, npm, cargo); Nix owns the toolchain and system tools.

Principle: templates are broad starting points; the deployed `flake.nix` is tuned precisely to the project's actual detected dependencies — add only what the project needs.

## Inputs

- `$ARGUMENTS`: optional template type — `python`, `rust`, `node`, `zig`, or `generic`.
- The cog nix template domain (`templates/nix/<type>`), or a caller-supplied `--template-root`.
- Current working directory: the target project.

## Cog Contract

`cog` must be installed and on `PATH`; a bare call fails legibly if it is missing. Detect the template type when the user did not provide one:

```bash
cog nix-devshell-detect --json
```

Detection classifies the project's language signals and maps a single recognized signal to `python|rust|node|zig`. A project with no recognized signal, or with ambiguous signals, resolves to `generic` with `ok:true` — nix detection always yields a usable target and never hard-fails. Pass an explicit type to override:

```bash
cog nix-devshell-detect --type "$TYPE" --json
```

The detection helper emits `{ok, project_root, template_root, requested_type, detected_type,
confidence, classification, signals, conflicts, template_dir, template_config, template_exists,
reason}`. `detected_type` is the template directory; `confidence` is `high` (single signal), `requested` (explicit `--type`), or `fallback` (generic).

Deploy the template after conflict policy is explicit, per file:

```bash
cog nix-devshell-apply \
  --type "$TYPE" \
  --flake-conflict "$FLAKE_POLICY" \
  --envrc-conflict "$ENVRC_POLICY" \
  --companion-conflict "$COMPANION_POLICY" \
  --json
```

The apply helper copies `flake.nix` and `.envrc`, plus `rust-toolchain.toml` for the `rust` type (the companion). Each destination has its own policy (`overwrite`, `skip`, or `abort`, default `abort`) and is guarded to stay inside the project root. It emits `{ok, project_root, template_root,
type, template_dir, copied[], skipped[], conflicts[], flake_conflict, envrc_conflict,
companion_conflict, reason}`. The helper never runs `nix flake lock`, edits `.gitignore`, or touches `flake.lock`.

Reconciling a pre-existing `flake.nix` or `.envrc` is judgment: inspect both files, decide the merge in prose, and use the helper only for safe copies. Never blind-overwrite an existing flake or envrc.

## Template refresh

Follow the shared refresh routine at `$(cog skill-refs path bootstrap/template-refresh-routine.md)` on every run: check freshness, review and update the shared template when stale or missing, stamp the review, then reconcile the target — installing when absent, tuning improvements when present. Use the freshness `check` JSON `/bootstrap` supplied in the brief; when it is absent, resolve the type with `nix-devshell-detect` and run it yourself:

```bash
cog bootstrap-template-review check --domain nix --type "$TYPE" --json
```

When `review.fresh` is `true`, reuse the cached `summary` and skip the flake research — go straight to tuning the deployed flake in the Workflow below. When it is `stale` or `missing`, web-research current flake / `nix develop` / nix-direnv practice for the type, update `skill-refs/templates/nix/<type>/` when justified, then stamp the review with `cog bootstrap-template-review stamp --domain nix --type "$TYPE"
...` — even when the conclusion is "no template change" — before reconciling `flake.nix` / `.envrc`. `stamp` fails fast when the template SoT is not writable; surface that. The `.gitignore` and CI files stay owned by their own domains.

## Workflow

1. Resolve the type. If `$ARGUMENTS` gives one, run `nix-devshell-detect --type "$TYPE"` to validate the template path. Otherwise run `nix-devshell-detect --json` and take `detected_type` (which is `generic` when nothing specific is recognized).

2. Analyze the project: manifests (`pyproject.toml`, `Cargo.toml`, `package.json`, `build.zig`), the runtime version it targets, native/system libraries it links, and any existing `flake.nix` / `.envrc`.

3. Deploy the template. Choose per-file conflict policies from the analysis; when a file already exists, reconcile it in prose rather than overwriting blindly, then apply only the safe copies:

   ```bash
   cog nix-devshell-apply --type "$TYPE" \
     --flake-conflict "$FLAKE_POLICY" --envrc-conflict "$ENVRC_POLICY" \
     --companion-conflict "$COMPANION_POLICY" --json
   ```

4. Tune `flake.nix` minimally to the detected dependencies:
   - add only the `packages` / `buildInputs` the project actually needs (its runtime, package manager, and any `-sys`/native system libraries such as `openssl`, `pkg-config`, `zlib`);
   - Python: pin the interpreter as the single source of truth and keep the `assert python.version == pkgs.poetry.python.version` guard so the venv cannot drift from the pin; keep the `LD_LIBRARY_PATH` line that exposes `libstdc++.so.6`/`libz.so.1` for manylinux wheels;
   - Rust: leave the version declaration in `rust-toolchain.toml` — the flake reads it via `fromRustupToolchainFile`; add `-sys` native deps to `buildInputs`/`nativeBuildInputs` as needed;
   - keep the `nixfmt-rfc-style`/`statix`/`deadnix` packages and the `formatter` output: the shared pre-commit Nix overlay runs them `language: system` off PATH, so the devShell must provide them;
   - **every `language: system` hook in the project's `.pre-commit-config.yaml` needs a named provider here.** Such hooks get no environment of their own and resolve off the ambient PATH, so an unprovided one fails only on someone else's machine. Read the config and check each `entry` against this `packages` list;
   - **keep `nodejs`/`go` when the config carries `node`/`golang` hooks.** pre-commit selects `system` for those languages only when it finds the runtime on PATH, and otherwise downloads a generic-glibc toolchain whose ELF interpreter (`/lib64/ld-linux-x86-64.so.2`) does not exist on a Nix host. Details, including why `lang_base.exe_exists` rejects a runtime installed under `$HOME`, are in `$(cog skill-refs path pre-commit/hook-language-resolution.md)`;
   - keep the flake lean: remove template packages the project does not use — but a package that backs a `language: system` hook is _used_, even though nothing in the project source imports it.

5. Establish auto-load. The `.envrc` is `use flake` (Python also layers the Poetry venv onto `PATH`). Do **not** add a `nix_direnv_version` probe: direnv's own `use_flake` passes `--profile "$(direnv_layout_dir)/flake-profile"`, and a Nix profile generation is a permanent GC root, so the devShell survives `nix-collect-garbage` without nix-direnv. nix-direnv buys evaluation caching — a preference, not a correctness requirement. Keep the Python venv-shadow guard, which addresses a real failure: `PATH_add` prepends, so a tool present in both the venv and the devShell resolves to the venv copy, and a PyPI binary wheel there cannot exec on a Nix host. The guard must **fail** the environment (`exit 1`) and run **before** `PATH_add` — direnv's `log_error` only prints, so a warning would still export the broken `PATH`. Its tool list must match exactly the tools the paired flake provides whose hooks are `language: system`. Interactive shells enter the devShell after a one-time `direnv allow` on `cd`. Non-interactive contexts (CI, agents, editor task runners, `bash -c`) need explicit activation — the prompt hook does not fire there. Wrap commands with `direnv exec . <cmd>` or `nix develop --command <cmd>`. See `cog skill-refs path nix/non-interactive-direnv.md`.

6. Generate CI steps that reuse the flake — run each task through `nix develop --command <task>` so CI uses the same pinned toolchain as the shell. Hand these steps to the CI scaffolding contract rather than writing CI files here.

7. Ensure `.gitignore` carries `.direnv/` and `/result`. The gitignore domain owns the `.gitignore` path; surface the required ignore fragments to it rather than editing `.gitignore` here. The nix fragment has a dedicated, type-independent, idempotent top-up that guarantees both lines land even when the `.gitignore` deliverable already exists:

   ```bash
   cog gitignore-apply --type nix --append --json
   ```

8. Present a summary: the deployed type, flake packages added or removed, the runtime pin, how to enter the shell (`direnv allow` / `nix develop`), the non-interactive command form, and next steps:

   ```bash
   nix flake lock        # on a host with nix + network; commit the generated flake.lock
   direnv allow          # trust the .envrc once for interactive cd
   ```

## Guardrails

- Never fabricate `flake.lock`; it is generated only on a host with `nix` and network access (`nix flake lock`) and then committed.
- Keep the flake minimal and reproducible: pin inputs, add only necessary packages, and do not turn a devShell into a full build system unless the project asks for it.
- Reconcile an existing `flake.nix` / `.envrc` in prose; ask before any destructive overwrite.
- Leave `.gitignore` writes to the gitignore domain; leave CI file writes to the CI scaffolding.
- Web-research current flake, `nix develop`, and nix-direnv practice as optional enhancers; the cog templates and this prose are sufficient on their own.
