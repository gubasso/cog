---
name: bootstrap-precommit
description: >
  Delegates deterministic project-type detection and template copying to
  the cog CLI while preserving hook research, template updates, conflict
  decisions, and repo-specific tailoring judgment in prose. Use when the user
  says "pre-commit", "set up pre-commit", "configure hooks", "add lint hooks",
  or "install pre-commit".
model: opus
effort: low
---

<!-- trigger-tests: "pre-commit", "set up pre-commit", "configure hooks", "add lint hooks", "install pre-commit" -->

# Bootstrap Pre-commit Skill

Set up a tailored `.pre-commit-config.yaml` for the current project by combining a broad cog template with repo-specific customization.

Principle: templates are broad and general; local configs are precise and tailored — repo-specific customization belongs in the local config.

## Boundary

This skill owns the project's pre-commit configuration. Its config must include an `editorconfig-checker` hook consistent with the shared `.editorconfig` baseline — a structural contract this skill honors. The `.editorconfig` file's own content is authored and aligned elsewhere; this skill neither writes nor tunes it.

## Inputs

- `$ARGUMENTS`: optional project type, such as `bash`, `python`, `rust`, `zig`, `c`, `node`, or `sveltekit`.
- Template directory: cog's `skill-refs/templates/pre-commit/` tree, or a caller-supplied `--template-root`.
- Current working directory: the target project.

The `markdown` template exists in the cog-owned template tree but is not auto-detected by this skill because the detection table does not include it. It remains reachable by explicit `--type markdown`.

The `markdown` template's spell checker is variant-selected via `--spell <typos|cspell>` (default `typos`). English-only knowledge bases use `typos`; knowledge bases with non-English content use `cspell` (English default plus per-file `<!-- cspell:dictionaries pt-br -->`). The apply helper copies the chosen variant's companion files (`_typos.toml`, or `cspell.config.yaml` + `project-words.txt` + `SPELLING.md`) and appends its hook stanza to the config. The language declaration that drives the choice is supplied by the caller; resolve it with `cog precommit-spell-select --languages <csv>` when a set of content languages is known. `--spell` has no effect on non-markdown types.

## Cog Contract

`cog` must be installed and on `PATH`; a bare call fails legibly if it is missing. Detect the project type when the user did not provide one:

```bash
cog precommit-detect --json
```

If detection is ambiguous, ask the user to choose from the helper's `conflicts[]`, then rerun with an explicit type:

```bash
cog precommit-detect --type "$TYPE" --json
```

The detection helper emits:

```json
{
  "ok": true,
  "project_root": "/repo",
  "template_root": "/repo/cog/skill-refs/templates/pre-commit",
  "requested_type": null,
  "detected_type": "rust",
  "confidence": "high",
  "classification": {},
  "signals": ["Cargo.toml"],
  "conflicts": [],
  "template_dir": "/repo/cog/skill-refs/templates/pre-commit/rust",
  "template_config": "/repo/cog/skill-refs/templates/pre-commit/rust/.pre-commit-config.yaml",
  "template_exists": true,
  "reason": null
}
```

Apply an existing template only after conflict policy is explicit. For `--type markdown`, pass `--spell "$SPELL"` (the resolved `typos` or `cspell` variant); omit it for other types:

```bash
cog precommit-apply-template \
  --type "$TYPE" \
  --spell "$SPELL" \
  --config-conflict "$CONFIG_POLICY" \
  --companion-conflict "$COMPANION_POLICY" \
  --json
```

Alongside the selected type's files, the helper always copies the shared `committed.toml` (commit-message linting) companion from the template root, governed by `--companion-conflict`. For `markdown`, it also copies the selected spell variant's companions and reports the choice in the `spell` and `spell_hook_appended` fields.

For every type, the helper also applies the shared Nix overlay: it copies `statix.toml` as a companion and appends a Nix hook block (`nixfmt` format, `statix`/`deadnix` gates, and a pre-push `nix flake check`) to the freshly-copied config, reporting it in `nix_hook_appended`. This governs each project's per-project flake devShell; the hooks run `language: system` off PATH, so the flake devShell must provide `nixfmt`/`statix`/`deadnix` (the bootstrap-nix templates do).

For every type **except `markdown`**, the helper also applies the shared markdown overlay: it copies `dprint.markdown.json` and `.markdownlint-cli2.jsonc` as companions and appends a markdown hook block (`dprint` unwrap with `textWrap: "never"`, the explicit relative-link guards, and `markdownlint-cli2`) to the freshly-copied config, reporting it in `markdown_hook_appended`. Every project carries docs/READMEs, so its markdown is formatted and linted uniformly. The `markdown` type is excluded because its own template carries the full markdown layer inline (plus KB-only extras). The `dprint` markdown hook runs `language: system` off PATH via a dedicated `--config dprint.markdown.json`, so `dprint` must be available.

The apply helper emits:

```json
{
  "ok": true,
  "project_root": "/repo",
  "template_root": "/repo/cog/skill-refs/templates/pre-commit",
  "type": "rust",
  "template_dir": "/repo/cog/skill-refs/templates/pre-commit/rust",
  "copied": [
    {
      "src": "/repo/cog/skill-refs/templates/pre-commit/rust/.pre-commit-config.yaml",
      "dst": "/repo/.pre-commit-config.yaml"
    }
  ],
  "skipped": [],
  "conflicts": [],
  "config_conflict": "abort",
  "companion_conflict": "abort",
  "spell": "typos",
  "spell_hook_appended": false,
  "nix_hook_appended": true,
  "markdown_hook_appended": true,
  "reason": null
}
```

The helper's conflict policies are only `overwrite`, `skip`, and `abort`. Merge is judgment-heavy and stays in this skill: inspect both files, decide the merge manually, then use the helper only for safe copies that remain.

## Template refresh

Follow the shared refresh routine at `$(cog skill-refs path bootstrap/template-refresh-routine.md)` on every run: check freshness, review and update the shared template when stale or missing, stamp the review, then reconcile the target — installing when absent, applying improvements when present. Use the freshness `check` JSON `/bootstrap` supplied in the brief; when it is absent, resolve the type with `precommit-detect` and run it yourself:

```bash
cog bootstrap-template-review check --domain precommit --type "$TYPE" --json
```

When `review.fresh` is `true`, reuse the cached `summary` and skip the hook research — go straight to tailoring and reconcile in the Workflow below. When it is `stale` or `missing`, do the hook research (steps 5-7), update `skill-refs/templates/pre-commit/<type>/` when justified, then stamp the review with `cog bootstrap-template-review stamp --domain precommit --type "$TYPE" ...` — even when the conclusion is "no template change" — before reconciling. `stamp` fails fast when the template SoT is not writable; surface that. The `editorconfig-checker` hook stays a verified reconcile postcondition (step 13).

## Workflow

1. Resolve project type. If `$ARGUMENTS` provides a type, run `precommit-detect --type "$TYPE"` to validate the template path. Otherwise run `precommit-detect --json`.

2. If detection reports no match or multiple matches, ask the user to pick a type. Do not guess from conflicting language signals.

3. If the template root is missing, stop and report the helper's reason.

4. If no template exists for the selected type, ask whether to create one. If confirmed, web search for best current pre-commit hooks for that project type. Read two or three existing templates for style and structure. Generate a broad template under the cog-owned template tree only with user approval.

5. Search for new general hooks relevant to the selected type. Prefer well-maintained repositories, recent releases, and official pre-commit ecosystem hooks where possible. Record candidates with repo URL, hook ID, and purpose.

6. Check existing hook repos in the template for latest release tags and maintenance status. Note version bumps, archived repos, and better-maintained replacements.

6b. **Read each pinned repo's `.pre-commit-hooks.yaml` at the tag being pinned.** A tag check alone cannot see the defects that matter most, because none of them is a version bump. Reconcile every stanza against that file:

- **the id still exists and is not a legacy alias** — upstream renames without removing (`ruff` → `ruff-check`, where bare `ruff` is marked `# Legacy alias`);
- **the upstream default `args:`** — overriding no args means inheriting upstream's, so any comment asserting a behavior must be backed by an explicit `args:` in the config. `typos` defaults to `[--write-changes, --force-exclude]` and therefore **auto-fixes** unless told otherwise;
- **whether a `<id>-system` / `-docker` / `-src` variant exists**, and which one this project's environment calls for.

1. Update the broad template when justified:
   - pin release tags, never branches;
   - **keep every repo's `rev:` identical across all templates that pin it** — one repo, one rev, tree-wide;
   - **prefer additive CLI flags over config-replacing ones.** Ruff's `--select` replaces the active rule selection from every resolved config file, so the project's own `select` stops applying and any per-file-ignores for the dropped rules become moot; use `--extend-select`. Verify with a representative input (`ruff check --stdin-filename <path> -`), not `--show-settings`, which reports the rule as enabled either way;
   - **use upstream's `-system` id when a local binary is wanted; never override `language:` on the default id** — the override reuses the default id's `entry`, which may be an installer script rather than the binary. This choice is environment-conditional: the default id is right when nothing provides the binary, the `-system` id when a devShell already does;
   - preserve the template's section order and comment style;
   - keep the housekeeping base consistent with existing templates;
   - keep `committed` as the single source of truth for commit-message linting;
   - keep the `editorconfig-checker` hook present, aligned with the shared `.editorconfig` baseline;
   - document `language: system` hooks with their external dependency, **and confirm the paired `flake.nix` (bootstrap-nix, same type) actually ships a provider for each**. Such hooks get no environment and resolve off the ambient PATH.

   The pre-commit internals behind these rules — `system` getting no env, `lang_base.exe_exists` rejecting `$HOME`, the `language_version: system` requirement for `node`/`golang` hooks with `additional_dependencies`, and the venv/devShell PATH-shadowing trap — live in `$(cog skill-refs path pre-commit/hook-language-resolution.md)`. Read it before changing a hook's `language`, `language_version`, or id.

2. Before copying to the project, inspect possible conflicts. Ask the user for the headline `.pre-commit-config.yaml` policy: overwrite, merge, or abort. For companion files, ask overwrite, skip, or abort as needed.

3. If the user chooses merge for `.pre-commit-config.yaml`, perform that merge in prose and targeted edits; do not ask `precommit-apply-template` to merge. For non-merge cases, pass explicit helper policies:

   ```bash
   cog precommit-apply-template \
     --type "$TYPE" \
     --spell "$SPELL" \
     --config-conflict "$CONFIG_POLICY" \
     --companion-conflict "$COMPANION_POLICY" \
     --json
   ```

4. Analyze the repository context: README, manifests, CI, tool configs, source layout, tests, and existing pre-commit config if preserved or merged.

5. Search for repo-specific hooks based on the actual stack. Examples include framework upgrades, type-checking integrations, migration linters, or CI config validators.

6. Tailor the local config:
   - add repo-specific hooks that provide clear value;
   - remove irrelevant hooks only when they genuinely do not apply;
   - adjust hook args for repo conventions;
   - add excludes only for generated, vendored, binary, external, or intentionally unmanaged paths;
   - tailor companion files such as `lychee.toml` or `.config/nextest.toml`.

7. Confirm the config carries an `editorconfig-checker` hook consistent with the shared `.editorconfig` baseline (the language templates ship it). This is a verified postcondition: when reconciling a pre-existing config that lacks the hook while an `.editorconfig` is present, add the hook rather than leaving it absent. Validate the config when the tool is available:

   ```bash
   pre-commit validate-config
   ```

8. Present a final summary: template hooks added, updated, or removed; local hooks added, removed, or adjusted; external tool requirements; and next commands:

   ```bash
   pre-commit install
   pre-commit run --all-files
   ```

## Guardrails

- Always pin hooks to tags, never branches or `HEAD`.
- Prefer well-maintained, widely used hook repositories.
- Keep all commit and push stages enforced; never recommend `SKIP=`, `--no-verify`, `git commit -n`, `pre-commit uninstall`, `core.hooksPath`, or disabling commit stages.
- Removing a hook is allowed only when it is irrelevant, obsolete, superseded, or broken beyond repair with a better replacement.
- Ask before destructive changes such as overwriting existing config or removing manually added hooks.
- Treat helper output as mechanics only. Hook selection, web-search enrichment, and tailoring remain skill judgment.
