---
name: bootstrap-installer
description: >
  Scaffold a project's install.sh, uninstall.sh, and shared install-common.sh
  with a verbose, TTY-aware, error-covered UX, tailored to the project's real
  payload, and wire install/uninstall/reinstall recipes into its justfile. Use
  when the user says "bootstrap-installer", "install.sh", "installer script",
  "set up install", or "install/uninstall scripts".
model: opus
effort: low
argument-hint: "[bash|generic|rust|python|node]"
---

<!-- trigger-tests: "bootstrap-installer", "install.sh", "installer script", "set up install", "install/uninstall scripts" -->

# Bootstrap installer scripts

Give the project an `install.sh`, `uninstall.sh`, and shared `install-common.sh` carrying the same install UX every bootstrapped project gets: leveled progress, a contextual error trap, the stdout-is-data / stderr-is-progress split, and disciplined exit codes (`0`/`1`/`130`/`143`). That shared UX standard is the point of the template — keep it intact through every tailoring.

The mechanics underneath it vary by language. `bash` and `generic` ship a manifest-driven PREFIX/XDG file-copy installer; `rust`, `python`, and `node` wrap the native toolchain (`cargo install`, `pipx install`, `npm install -g`) behind the same surface.

This skill owns the three scripts. It also injects recipes into the project's justfile when asked, but it never creates that file — the task-runner domain does.

Follow the shared routine at `$(cog skill-refs path bootstrap/domain-worker-routine.md)`:

```bash
cog bootstrap-template-review check --domain installer --type "$TYPE" --json
```

A fresh review means reuse the cached `summary` and go straight to tailoring; stale or missing means review current install conventions for the type — XDG/PREFIX layout for the manifest-copy family, native-toolchain install/uninstall flags for the native-wrap family — update `skill-refs/templates/installer/<type>/` or the shared `install-common.sh` when justified, and `stamp` before reconciling.

## Detect and apply

```bash
cog installer-detect [--type "$TYPE"] --json
```

The detector resolves `rust`, `python`, `node`, and `bash` directly. When it reports no match, several matches, or a language with no installer template (such as `c` or `zig`), ask the user whether to use the language-agnostic `generic` installer or a specific type, then re-run with `--type`. Do not guess from conflicting signals.

These are whole-file generated artifacts, so the conflict policy is `overwrite`, `skip`, or `abort`, defaulting to `abort`. When any of the three scripts already exists, ask before applying — a hand-edited installer is replaced only with explicit approval.

```bash
cog installer-apply --type "$TYPE" --conflict "$POLICY" [--wire-taskrunner] --json
```

Scripts land at mode `0755`. `--wire-taskrunner` injects `install`/`uninstall`/`reinstall` recipes into an existing justfile inside a managed `# --- cog installer ---` block, adding only what is missing and staying idempotent, so `just install` works out of the box. With no justfile present, `wire_target` is null and `wire_reason` explains it — the copy still succeeds, because wiring is best-effort. Whether to wire at all is this skill's call.

## Tailor

The generated scripts carry placeholders that only the project can fill:

- **Manifest-copy (`bash`, `generic`):** edit the `PROJECT CONFIGURATION` block — set `project_name` and fill `copy_trees`, `copy_files`, `bin_links`, `owned_clear`, and `manifest_roots` from the project's real payload and install roots. Keep `owned_clear` and `manifest_roots` scoped to project-owned paths, so uninstall can never reach outside them.
- **Native-wrap (`rust`, `python`, `node`):** set `project_name`, and set `package_name` in `uninstall.sh` to the installed package name from the project manifest.

## Verify and close

Run `shellcheck` and `shfmt` on the tailored scripts when available. Then prove the round trip: a dry install and uninstall in a throwaway `PREFIX`/`HOME` for the manifest-copy family, or a preflight check that the required toolchain is present for the native-wrap family.

Report the type applied, the files written, the payload or package tailored, and the next commands (`./install.sh`, `./uninstall.sh`, or `just install` when wired).
