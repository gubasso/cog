---
name: bootstrap-installer
description: >
  Delegates deterministic project-type detection and installer-script copying to
  the cog CLI while preserving payload tailoring, conflict decisions, and
  task-runner wiring judgment in prose. Scaffolds a project's install.sh,
  uninstall.sh, and shared install-common.sh with a verbose, error-covered UX.
  Use when the user says "install.sh", "installer script", "set up install",
  "install/uninstall scripts", or "make just install work".
model: opus
effort: low
---

<!-- trigger-tests: "install.sh", "installer script", "set up install", "install/uninstall scripts", "make just install work" -->

# Bootstrap Installer Skill

Scaffold a project's `install.sh`, `uninstall.sh`, and shared `install-common.sh` from a broad cog template tailored to the project's language, giving every bootstrapped project the same verbose, TTY-aware, error-covered install UX (leveled progress, a contextual error trap, and disciplined exit codes `0`/`1`/`130`/`143`).

Principle: the install-UX standard is shared; the install mechanics vary by language. `bash` and `generic` ship a manifest-driven PREFIX/XDG file-copy installer; `rust`, `python`, and `node` wrap the native toolchain (`cargo install`, `pipx install`, `npm install -g`) behind the same UX.

## Boundary

This skill owns the project's `install.sh`, `uninstall.sh`, and `install-common.sh`. It also injects `install`/`uninstall`/`reinstall` recipes into an existing task-runner file when asked, but it neither creates nor owns that runner file — the task-runner scaffold is authored elsewhere.

## Inputs

- `$ARGUMENTS`: optional installer type, one of `bash`, `generic`, `rust`, `python`, or `node`.
- Template directory: cog's `skill-refs/templates/installer/` tree, or a caller-supplied `--template-root`.
- Current working directory: the target project.

## Cog Contract

`cog` must be installed and on `PATH`; a bare call fails legibly if it is missing. Detect the installer type when the user did not provide one:

```bash
cog installer-detect --json
```

The detector maps the project's language classification to a template type and emits `{ok,
detected_type, confidence, template_dir, template_exists, conflicts, signals, reason}`. It resolves `rust`, `python`, `node`, and `bash` directly. When it reports no match (`reason` is `could not detect template type`), multiple matches, or a language with no installer template (such as `c` or `zig`), fall back to the language-agnostic `generic` installer — confirm with the user, then rerun with an explicit type:

```bash
cog installer-detect --type "$TYPE" --json
```

Apply the selected type only after conflict policy is explicit. These are whole-file, generated artifacts, so the policy is `overwrite`, `skip`, or `abort` (default `abort`); pass `overwrite` only when refreshing files the user agrees to replace:

```bash
cog installer-apply --type "$TYPE" --conflict "$POLICY" --json
```

`installer-apply` copies the type's `install.sh` and `uninstall.sh` plus the shared `install-common.sh` companion to the project root at mode `0755`, and emits `{ok, type, copied[],
skipped[], conflicts[], wired[], wire_target, wire_reason, conflict, reason}`.

To make `just install` / `make install` work out of the box, wire the recipes into an existing runner file in the same call. This injects `install`/`uninstall`/`reinstall` recipes inside a managed `# --- cog installer ---` block, adds only the targets the file is missing, and is idempotent:

```bash
cog installer-apply --type "$TYPE" --conflict "$POLICY" --wire-taskrunner just --json
```

When no runner file is present, `wire_target` is null and `wire_reason` explains it — the copy still succeeds; wiring is best-effort. Recipe selection and whether to wire at all stay this skill's judgment.

## Template refresh

Follow the shared refresh routine at `$(cog skill-refs path bootstrap/template-refresh-routine.md)` on every run: check freshness, review and update the shared template when stale or missing, stamp the review, then reconcile the target — installing when absent, applying improvements when present. Use the freshness `check` JSON `/bootstrap` supplied in the brief; when it is absent, resolve the type with `installer-detect` and run it yourself:

```bash
cog bootstrap-template-review check --domain installer --type "$TYPE" --json
```

When `review.fresh` is `true`, reuse the cached `summary` and skip the research — go straight to tailoring and reconcile in the Workflow below. When it is `stale` or `missing`, review current install conventions for the selected type (XDG/PREFIX layout for the manifest-copy family, native-toolchain install/uninstall flags for the native-wrap family), update `skill-refs/templates/installer/<type>/` (or the shared `install-common.sh`) when justified, then stamp the review with `cog
bootstrap-template-review stamp --domain installer --type "$TYPE" ...` — even when the conclusion is "no template change" — before reconciling. `stamp` fails fast when the template SoT is not writable; surface that.

## Workflow

1. Resolve installer type. If `$ARGUMENTS` provides a type, run `installer-detect --type "$TYPE"` to validate the template path. Otherwise run `installer-detect --json`.

2. If detection reports no match, multiple matches, or an unsupported language, ask the user whether to use the `generic` installer or a specific type. Do not guess from conflicting language signals.

3. If the template root is missing, stop and report the helper's reason.

4. Inspect conflicts. When `install.sh`, `uninstall.sh`, or `install-common.sh` already exist, ask the user for the conflict policy before applying. Preserve hand-edited scripts unless the user approves replacement.

5. Apply the template:

   ```bash
   cog installer-apply --type "$TYPE" --conflict "$POLICY" --json
   ```

6. Tailor the generated scripts to the project. This is judgment and stays in prose:
   - manifest-copy (`bash`, `generic`): edit the `PROJECT CONFIGURATION` block — set `project_name` and fill `copy_trees`, `copy_files`, `bin_links`, `owned_clear`, and `manifest_roots` to the project's real payload and install roots. Keep `owned_clear` limited to project-owned paths.
   - native-wrap (`rust`, `python`, `node`): set `project_name`, and set `package_name` in `uninstall.sh` to the installed package name from the project manifest.

7. Wire the task runner when one is present and the user wants `just install` to work. Rerun with `--wire-taskrunner just` or `--wire-taskrunner make` to inject the recipes idempotently, or add them by hand if the runner uses a nonstandard layout.

8. Verify the result. Run `shellcheck`/`shfmt` on the tailored scripts when available, then a dry install/uninstall in a throwaway `PREFIX`/`HOME` for the manifest-copy family, or a preflight check (the required toolchain present) for the native-wrap family.

9. Present a final summary: the type applied, the files written, the payload or package tailored, and the next commands (`./install.sh`, `./uninstall.sh`, or `just install` when wired).

## Guardrails

- Keep the shared UX standard intact: the leveled messages, the ERR trap, the stdout-is-data / stderr-is-progress split, and the exit-code contract are the point of the template.
- Default to `abort` on conflict; replace an existing installer only with explicit user approval.
- Keep `owned_clear` and `manifest_roots` scoped to project-owned paths so uninstall never reaches outside the project's install roots.
- Treat helper output as mechanics only. Payload tailoring, package naming, conflict decisions, and task-runner wiring remain skill judgment.
