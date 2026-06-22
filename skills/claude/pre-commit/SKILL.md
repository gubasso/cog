---
name: pre-commit
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

# Pre-commit Skill

Set up a tailored `.pre-commit-config.yaml` for the current project by combining a broad cog
template with repo-specific customization. Every setup also establishes a `.editorconfig` and its
`editorconfig-checker` hook, with the `.editorconfig` aligned to the project's active formatters and
linters.

Principle: templates are broad and general; local configs are precise and tailored — repo-specific
customization belongs in the local config.

## Inputs

- `$ARGUMENTS`: optional project type, such as `bash`, `python`, `rust`, `zig`, `c`, `node`, or
  `sveltekit`.
- Template directories: cog's `skill-refs/templates/pre-commit/` and `skill-refs/templates/editorconfig/`
  trees, or a caller-supplied `--template-root`.
- Current working directory: the target project.

The `markdown` template exists in the cog-owned template tree but is not auto-detected by this skill
because the detection table does not include it. It remains reachable by explicit `--type markdown`.

## Cog Contract

`cog` must be installed and on `PATH`; a bare call fails legibly if it is
missing. Detect the project type when the user did not provide one:

```bash
cog precommit-detect --json
```

If detection is ambiguous, ask the user to choose from the helper's `conflicts[]`, then rerun with
an explicit type:

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

Apply an existing template only after conflict policy is explicit:

```bash
cog precommit-apply-template \
  --type "$TYPE" \
  --config-conflict "$CONFIG_POLICY" \
  --companion-conflict "$COMPANION_POLICY" \
  --json
```

Alongside the selected type's files, the helper always copies the shared `committed.toml`
(commit-message linting) companion from the template root, governed by `--companion-conflict`.

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
  "reason": null
}
```

The helper's conflict policies are only `overwrite`, `skip`, and `abort`. Merge is judgment-heavy
and stays in this skill: inspect both files, decide the merge manually, then use the helper only for
safe copies that remain.

EditorConfig is its own cog-owned template domain. Detect and deploy the matching `.editorconfig`:

```bash
cog editorconfig-detect --json
cog editorconfig-apply --type "$TYPE" --conflict "$EDITORCONFIG_POLICY" --json
```

`editorconfig-detect` emits the same shape as `precommit-detect` (with `template_root` under
`skill-refs/templates/editorconfig` and `template_config` ending in `.editorconfig`).
`editorconfig-apply` copies that one file to `<project>/.editorconfig` and emits
`{ok, type, template_dir, copied[], skipped[], conflicts[], conflict, reason}`. Its `--conflict`
policy is `overwrite`, `skip`, or `abort` (default `abort`); reconciling an existing project
`.editorconfig` is judgment that stays in this skill.

## Workflow

1. Resolve project type. If `$ARGUMENTS` provides a type, run `precommit-detect --type "$TYPE"` to
   validate the template path. Otherwise run `precommit-detect --json`.

2. If detection reports no match or multiple matches, ask the user to pick a type. Do not guess from
   conflicting language signals.

3. If the template root is missing, stop and report the helper's reason.

4. If no template exists for the selected type, ask whether to create one. If confirmed, web search
   for best current pre-commit hooks for that project type. Read two or three existing templates for
   style and structure. Generate a broad template under the cog-owned template tree only with user
   approval.

5. Search for new general hooks relevant to the selected type. Prefer well-maintained repositories,
   recent releases, and official pre-commit ecosystem hooks where possible. Record candidates with
   repo URL, hook ID, and purpose.

6. Check existing hook repos in the template for latest release tags and maintenance status. Note
   version bumps, archived repos, and better-maintained replacements.

7. Update the broad template when justified:
   - pin release tags, never branches;
   - preserve the template's section order and comment style;
   - keep the housekeeping base consistent with existing templates;
   - keep `committed` as the single source of truth for commit-message linting;
   - keep the `editorconfig-checker` hook present, aligned with the shared `.editorconfig` baseline;
   - document `language: system` hooks with their external dependency.

8. Before copying to the project, inspect possible conflicts. Ask the user for the headline
   `.pre-commit-config.yaml` policy: overwrite, merge, or abort. For companion files, ask
   overwrite, skip, or abort as needed.

9. If the user chooses merge for `.pre-commit-config.yaml`, perform that merge in prose and targeted
   edits; do not ask `precommit-apply-template` to merge. For non-merge cases, pass explicit helper
   policies:

   ```bash
   cog precommit-apply-template \
     --type "$TYPE" \
     --config-conflict "$CONFIG_POLICY" \
     --companion-conflict "$COMPANION_POLICY" \
     --json
   ```

10. Analyze the repository context: README, manifests, CI, tool configs, source layout, tests, and
    existing pre-commit config if preserved or merged.

11. Search for repo-specific hooks based on the actual stack. Examples include framework upgrades,
    type-checking integrations, migration linters, or CI config validators.

12. Tailor the local config:
    - add repo-specific hooks that provide clear value;
    - remove irrelevant hooks only when they genuinely do not apply;
    - adjust hook args for repo conventions;
    - add excludes only for generated, vendored, binary, external, or intentionally unmanaged paths;
    - tailor companion files such as `lychee.toml` or `.config/nextest.toml`.

13. Establish and align `.editorconfig`. Deploy the matching template with `cog editorconfig-apply`
    (reconcile a pre-existing project `.editorconfig` in prose rather than overwriting it), and confirm
    the config carries the `editorconfig-checker` hook (the language templates ship it). Align the
    settings with the project's active formatters and linters so the checker never fights them:
    - add the project's language indent blocks to match its formatter: `[*.rs]` and `[*.zig]` space 4
      (rustfmt, zig fmt); `[*.py]` space 4 (ruff-format); `[*.{sh,bash,bats}]` space 2 (shfmt `-i 2`);
      `[*.{js,jsx,ts,tsx,svelte,vue,css,scss}]` space 2 (prettier `tabWidth`); leave C indent to
      clang-format. The shared baseline already covers data formats (`json`/`yaml`/`toml` space 2)
      and `Makefile` (tab);
    - set `max_line_length` per glob only where a formatter or linter enforces a width (and
      `max_line_length = off` for prose globs such as `[*.md]`);
    - leave `insert_final_newline` and `trim_trailing_whitespace` owned by the housekeeping hooks,
      and pass `-disable-insert-final-newline` to editorconfig-checker so final-newline ownership is
      not duplicated;
    - exclude `*.md` from editorconfig-checker, which mis-parses fenced blocks; markdown stays owned
      by the markdown tooling, with `[*.md] trim_trailing_whitespace = false` preserving hard breaks.

14. Present a final summary: template hooks added, updated, or removed; local hooks added, removed,
    or adjusted; `.editorconfig` settings established or aligned; external tool requirements; and
    next commands:

    ```bash
    pre-commit install
    pre-commit run --all-files
    ```

## Guardrails

- Always pin hooks to tags, never branches or `HEAD`.
- Prefer well-maintained, widely used hook repositories.
- Keep all commit and push stages enforced; never recommend `SKIP=`, `--no-verify`,
  `git commit -n`, `pre-commit uninstall`, `core.hooksPath`, or disabling commit stages.
- Removing a hook is allowed only when it is irrelevant, obsolete, superseded, or broken beyond
  repair with a better replacement.
- Ask before destructive changes such as overwriting existing config or removing manually added
  hooks.
- Treat helper output as mechanics only. Hook selection, web-search enrichment, and tailoring remain
  skill judgment.
