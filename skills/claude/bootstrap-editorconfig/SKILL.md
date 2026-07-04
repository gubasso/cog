---
name: bootstrap-editorconfig
description: >
  Owns .editorconfig authoring plus formatter/linter alignment for the current
  project, delegating deterministic detection and template copying to the cog
  CLI while keeping alignment judgment and web research in prose. Use when the
  user says "editorconfig", "set up editorconfig", or "configure editorconfig".
model: opus
effort: low
---

<!-- trigger-tests: "editorconfig", "set up editorconfig", "configure editorconfig" -->

# Bootstrap EditorConfig Skill

Author a tailored `.editorconfig` for the current project by combining a broad cog template with
per-language alignment to the project's active formatters and linters, so an `editorconfig-checker`
run never fights the tools that own formatting.

Principle: templates are broad and general; the project `.editorconfig` is precise and aligned —
every indent block and width setting matches the tool that actually enforces it.

## Boundary

This skill owns `.editorconfig` content: its sections, indent blocks, widths, and exclusions. The
project's hook configuration is expected to carry an `editorconfig-checker` hook consistent with this
baseline; that hook's presence is a structural contract ensured elsewhere and is not authored here.

## Inputs

- `$ARGUMENTS`: optional project type, such as `bash`, `python`, `rust`, `zig`, `c`, `node`, or
  `sveltekit`.
- Template directory: cog's `skill-refs/templates/editorconfig/` tree, or a caller-supplied
  `--template-root`.
- Current working directory: the target project.

## Cog Contract

`cog` must be installed and on `PATH`; a bare call fails legibly if it is missing. Detect the project
type when the user did not provide one:

```bash
cog editorconfig-detect --json
```

If detection is ambiguous, ask the user to choose from the helper's `conflicts[]`, then rerun with an
explicit type:

```bash
cog editorconfig-detect --type "$TYPE" --json
```

The detection helper emits:

```json
{
  "ok": true,
  "project_root": "/repo",
  "template_root": "/repo/cog/skill-refs/templates/editorconfig",
  "requested_type": null,
  "detected_type": "rust",
  "confidence": "high",
  "classification": {},
  "signals": ["Cargo.toml"],
  "conflicts": [],
  "template_dir": "/repo/cog/skill-refs/templates/editorconfig/rust",
  "template_config": "/repo/cog/skill-refs/templates/editorconfig/rust/.editorconfig",
  "template_exists": true,
  "reason": null
}
```

Deploy the matching baseline after conflict policy is explicit:

```bash
cog editorconfig-apply --type "$TYPE" --conflict "$EDITORCONFIG_POLICY" --json
```

`editorconfig-apply` copies that one file to `<project>/.editorconfig` and emits
`{ok, type, template_dir, copied[], skipped[], conflicts[], conflict, reason}`. Its `--conflict`
policy is `overwrite`, `skip`, or `abort` (default `abort`). Reconciling a pre-existing project
`.editorconfig` is judgment that stays in this skill: inspect the existing file and merge in prose
rather than blind-overwriting a config the project already tuned.

## Template refresh

Follow the shared refresh routine at `$(cog skill-refs path bootstrap/template-refresh-routine.md)` on
every run: check freshness, review and update the shared template when stale or missing, stamp the
review, then reconcile the target — installing when absent, aligning improvements when present. Use the
freshness `check` JSON `/bootstrap` supplied in the brief; when it is absent, resolve the type with
`editorconfig-detect` and run it yourself:

```bash
cog bootstrap-template-review check --domain editorconfig --type "$TYPE" --json
```

When `review.fresh` is `true`, reuse the cached `summary` and skip the spec research — go straight to
aligning the baseline in the Workflow below. When it is `stale` or `missing`, do the spec research
(step 4), update `skill-refs/templates/editorconfig/<type>/` when justified, then stamp the review with
`cog bootstrap-template-review stamp --domain editorconfig --type "$TYPE" ...` — even when the conclusion
is "no template change" — before reconciling the project `.editorconfig`. `stamp` fails fast when the
template SoT is not writable; surface that.

## Workflow

1. Resolve project type. If `$ARGUMENTS` provides a type, run `editorconfig-detect --type "$TYPE"` to
   validate the template path. Otherwise run `editorconfig-detect --json`.

2. If detection reports no match or multiple matches, ask the user to pick a type. Do not guess from
   conflicting language signals.

3. If the template root is missing, stop and report the helper's reason.

4. Web-search current `.editorconfig` best settings and the EditorConfig spec (`editorconfig.org`,
   `spec.editorconfig.org`) as enhancers: confirm `root = true`, section precedence, and the
   indent/newline/charset property names before aligning. These are optional; proceed from the cog
   template and this prose when offline.

5. Establish the baseline. Deploy the matching template with `cog editorconfig-apply`, reconciling a
   pre-existing project `.editorconfig` in prose rather than overwriting it.

6. Align settings with the project's active formatters and linters so the checker never fights them:
   - add the project's language indent blocks to match its formatter: `[*.rs]` and `[*.zig]` space 4
     (rustfmt, zig fmt); `[*.py]` space 4 (ruff-format); `[*.{sh,bash,bats}]` space 2 (shfmt `-i 2`);
     `[*.{js,jsx,ts,tsx,svelte,vue,css,scss}]` space 2 (prettier `tabWidth`); leave C indent to
     clang-format. The shared baseline already covers data formats (`json`/`yaml`/`toml` space 2) and
     `Makefile` (tab);
   - set `max_line_length` per glob only where a formatter or linter enforces a width, and
     `max_line_length = off` for prose globs such as `[*.md]`;
   - leave `insert_final_newline` and `trim_trailing_whitespace` owned by the housekeeping hooks, and
     pass `-disable-insert-final-newline` to editorconfig-checker so final-newline ownership is not
     duplicated;
   - exclude `*.md` from editorconfig-checker, which mis-parses fenced blocks; markdown stays owned by
     the markdown tooling, with `[*.md] trim_trailing_whitespace = false` preserving hard breaks.

7. Present a final summary: the baseline deployed or reconciled, the indent blocks and widths aligned
   to each formatter, the final-newline and markdown exclusions applied, and any formatter or linter
   whose configured width the `.editorconfig` now mirrors.

## Guardrails

- Keep `.editorconfig` aligned to the tool that owns each format; add an indent block or width only
  when a formatter or linter enforces it.
- Reconcile a pre-existing `.editorconfig` in prose; ask before overwriting settings the project
  already tuned.
- Treat helper output as mechanics only. Alignment decisions and web-search enrichment remain skill
  judgment.
