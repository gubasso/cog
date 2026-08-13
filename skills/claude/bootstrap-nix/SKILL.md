---
name: bootstrap-nix
description: >
  Give the project a reproducible per-project development environment: a
  flake.nix pinning its toolchain, an .envrc direnv loads automatically, and CI
  steps that reuse the same flake. Use when the user says "bootstrap-nix", "set
  up nix", "nix devshell", "add a flake", or "nix develop".
model: opus
effort: low
argument-hint: "[python|rust|node|zig|generic]"
---

<!-- trigger-tests: "bootstrap-nix", "set up nix", "nix devshell", "add a flake", "nix develop" -->

# Bootstrap Nix devshell

Give the project a reproducible development environment: a `flake.nix` that pins its toolchain, an `.envrc` that direnv loads automatically, and CI that reuses the same flake. Nix owns the toolchain and system tools; dependency resolution stays with the project's own package manager (Poetry, npm, cargo).

The template is a starting point; the deployed flake is tuned to the project's actual detected dependencies. Add only what the project needs — and remove template packages it does not use.

Follow the shared routine at `$(cog skill-refs path bootstrap/domain-worker-routine.md)`:

```bash
cog bootstrap-template-review check --domain nix --type "$TYPE" --json
```

A fresh review means reuse the cached `summary` and go straight to tuning; stale or missing means research current flake / `nix develop` / nix-direnv practice for the type, update `skill-refs/templates/nix/<type>/` when justified, and `stamp` before reconciling.

## Detect and deploy

```bash
cog nix-devshell-detect [--type "$TYPE"] --json
```

Detection maps a single recognized language signal to `python`, `rust`, `node`, or `zig`. No recognized signal, or ambiguous signals, resolves to `generic` with `ok:true` — nix detection always yields a usable target and never hard-fails. `confidence` reads `high` (single signal), `requested` (explicit `--type`), or `fallback` (generic).

Before deploying, read the project: its manifests, the runtime version it targets, the native libraries it links, and any existing `flake.nix` / `.envrc`.

```bash
cog nix-devshell-apply --type "$TYPE" \
  --flake-conflict "$FLAKE_POLICY" --envrc-conflict "$ENVRC_POLICY" \
  --companion-conflict "$COMPANION_POLICY" --json
```

It copies `flake.nix` and `.envrc`, plus `rust-toolchain.toml` for the `rust` type. Each destination carries its own policy. The helper never runs `nix flake lock`, edits `.gitignore`, or touches `flake.lock` — and `flake.lock` is never fabricated here either; it is generated on a host with nix and network, then committed.

Reconcile a pre-existing flake or envrc in prose: read both, decide the merge, and use the helper only for the safe copies. Never blind-overwrite either one.

## Tune the flake

Add only the `packages` / `buildInputs` the project actually needs — its runtime, package manager, and any `-sys`/native system libraries such as `openssl`, `pkg-config`, `zlib`. Then, by type:

- **Python:** pin the interpreter as the single source of truth and keep the `assert python.version == pkgs.poetry.python.version` guard so the venv cannot drift from the pin. Keep the `LD_LIBRARY_PATH` line exposing `libstdc++.so.6`/`libz.so.1` for manylinux wheels.
- **Rust:** leave the version declaration in `rust-toolchain.toml` — the flake reads it via `fromRustupToolchainFile`. Add `-sys` native deps to `buildInputs`/`nativeBuildInputs`.

Three rules decide whether a package stays, and all three come from the same fact — a `language: system` hook gets no environment of its own and resolves off the ambient PATH:

- **Every `language: system` hook in the project's `.pre-commit-config.yaml` needs a named provider here.** An unprovided one fails only on someone else's machine. Read the config and check each `entry` against the `packages` list. The Nix overlay's `nixfmt`/`statix`/`deadnix` and its `formatter` output are exactly this case.
- **Keep `nodejs`/`go` when the config carries `node`/`golang` hooks.** pre-commit selects `system` for those languages only when it finds the runtime on PATH; otherwise it downloads a generic-glibc toolchain whose ELF interpreter (`/lib64/ld-linux-x86-64.so.2`) does not exist on a Nix host. That, and why `lang_base.exe_exists` rejects a runtime installed under `$HOME`, are in `$(cog skill-refs path pre-commit/hook-language-resolution.md)`.
- **Keep the flake lean otherwise.** A package that backs a `language: system` hook is _used_, even though nothing in the project source imports it. Everything else the project does not reach for comes out.

Keep the devShell a devShell: pin inputs, and do not grow it into a full build system unless the project asks.

## Auto-load

The `.envrc` is `use flake` (Python also layers the Poetry venv onto `PATH`).

Do **not** add a `nix_direnv_version` probe. direnv's own `use_flake` passes `--profile "$(direnv_layout_dir)/flake-profile"`, and a Nix profile generation is a permanent GC root, so the devShell survives `nix-collect-garbage` without nix-direnv. nix-direnv buys evaluation caching — a preference, not a correctness requirement.

Keep the Python `.envrc` lean: `use flake`, locate the venv, layer it. `PATH_add` prepends, so a tool present in both the venv and the devShell resolves to the venv copy, and a PyPI binary wheel there cannot exec on a Nix host. Hold that invariant where it is actionable — the flake's `PRECONDITION` note and the pyproject dev group — so a violation surfaces as a hook failure on the next `pre-commit run`, rather than as a fatal `.envrc` that aborts before `use flake` puts `poetry` on `PATH` and so denies the shell the `poetry sync` that would fix it.

Interactive shells enter the devShell after a one-time `direnv allow` on `cd`. Non-interactive contexts — CI, agents, editor tasks, `bash -c` — need explicit activation, because the prompt hook never fires there: wrap commands with `direnv exec . <cmd>` or `nix develop --command <cmd>`. See `$(cog skill-refs path nix/non-interactive-direnv.md)`.

## Fragments and close

Two paths belong to other domains; surface them rather than writing them:

- **CI steps** run each task through `nix develop --command <task>` so CI uses the same pinned toolchain. Hand them to the CI domain.
- **`.gitignore`** needs `.direnv/` and `/result`. The repo domain owns that path, and the nix fragment has a dedicated, type-independent, idempotent top-up that guarantees both lines land even when the `.gitignore` deliverable already exists:

  ```bash
  cog gitignore-apply --type nix --append --json
  ```

Report the deployed type, the flake packages added or removed, the runtime pin, how to enter the shell, and the non-interactive command form.

```bash
nix flake lock        # on a host with nix + network; commit the generated flake.lock
direnv allow          # trust the .envrc once for interactive cd
```
