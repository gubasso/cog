---
name: bootstrap-lint
description: >
  Set up a project's code-style enforcement: an .editorconfig aligned to the
  formatters that actually own each file type, and a .pre-commit-config.yaml
  whose hooks are pinned, current, and consistent with that baseline. Use when
  the user says "bootstrap-lint", "pre-commit", "set up pre-commit", "configure
  hooks", "add lint hooks", "editorconfig", or "set up editorconfig".
model: opus
effort: low
argument-hint: "[project type: bash|python|rust|zig|c|node|sveltekit|markdown]"
---

<!-- trigger-tests: "bootstrap-lint", "pre-commit", "set up pre-commit", "configure hooks", "add lint hooks", "editorconfig", "set up editorconfig" -->

# Bootstrap code-style enforcement

Give the project one coherent code-style layer: `.editorconfig` declares what each file type looks like, and `.pre-commit-config.yaml` enforces it. They are one domain with two files because they only work when they agree — an `editorconfig-checker` hook that fights the project's formatter is worse than no hook. Writing both here is what keeps them aligned.

Templates are broad and general; the project's files are precise and tailored. Every indent block matches the tool that actually enforces it, and every hook is pinned to a tag that was read, not guessed.

Run the shared routine at `$(cog skill-refs path bootstrap/domain-worker-routine.md)` twice — once for the `editorconfig` domain, once for `precommit` — in that order, so the hook config is written against a baseline that already exists. Each pass carries its own freshness gate and its own stamp:

```bash
cog bootstrap-template-review check --domain editorconfig --type "$TYPE" --json
cog bootstrap-template-review check --domain precommit    --type "$TYPE" --json
```

When the orchestrator supplied both `check` payloads in the brief, use those. A `review.fresh` of `true` means reuse the cached `summary` and skip that domain's research; otherwise research, update the template, and `stamp` before reconciling.

## Inputs

`$ARGUMENTS` is an optional project type (`bash`, `python`, `rust`, `zig`, `c`, `node`, `sveltekit`, `markdown`); otherwise `cog editorconfig-detect --json` and `cog precommit-detect --json` resolve it. When either reports no match or several, ask the user to pick from its `conflicts[]` and re-run with `--type "$TYPE"`. Never guess from conflicting language signals.

`markdown` is reachable only by explicit `--type markdown`; the detection table does not infer it.

## EditorConfig baseline

Deploy the matching template, then align it:

```bash
cog editorconfig-apply --type "$TYPE" --conflict "$POLICY" --json
```

Align every setting to the tool that owns that format, so the checker never fights it:

- **Indent blocks** follow the formatter: `[*.rs]` and `[*.zig]` space 4 (rustfmt, zig fmt); `[*.py]` space 4 (ruff-format); `[*.{sh,bash,bats}]` space 2 (shfmt `-i 2`); `[*.{js,jsx,ts,tsx,svelte,vue,css,scss}]` space 2 (prettier `tabWidth`). Leave C indent to clang-format. The shared baseline already covers `json`/`yaml`/`toml` at space 2.
- **`max_line_length`** goes on a glob only where a formatter or linter enforces a width; use `max_line_length = off` for prose globs such as `[*.md]`.
- **`insert_final_newline` and `trim_trailing_whitespace`** stay owned by the housekeeping hooks. Pass `-disable-insert-final-newline` to editorconfig-checker so final-newline ownership is not duplicated.
- **Exclude `*.md` from editorconfig-checker**, which mis-parses fenced blocks. Markdown stays owned by the markdown tooling, with `[*.md] trim_trailing_whitespace = false` preserving hard breaks.

Add an indent block or width only when a formatter or linter actually enforces it. Reconcile a pre-existing `.editorconfig` in prose — inspect it and merge — rather than overwriting settings the project already tuned.

## Pre-commit hooks

```bash
cog precommit-apply-template --type "$TYPE" --spell "$SPELL" \
  --config-conflict "$CONFIG_POLICY" --companion-conflict "$COMPANION_POLICY" --json
```

Beyond the type's own files the helper copies `committed.toml` (commit-message linting) and applies two shared overlays, reporting each in `nix_hook_appended` and `markdown_hook_appended`:

- **Nix overlay**, every type: `statix.toml` plus a hook block (`nixfmt` format, `statix`/`deadnix` gates, pre-push `nix flake check`). These run `language: system` off PATH, so the project's flake devShell must provide the three binaries — the nix domain's templates do.
- **Markdown overlay**, every type except `markdown`: `dprint.markdown.json` and `.markdownlint-cli2.jsonc` plus a hook block (`dprint` unwrap with `textWrap: "never"`, the relative-link guards, `markdownlint-cli2`). The `markdown` type carries this inline already. The `dprint` hook is `language: system`, so `dprint` must be on PATH.

For `--type markdown`, `--spell` selects the checker variant (default `typos`): English-only content uses `typos`, mixed-language content uses `cspell` with per-file `<!-- cspell:dictionaries pt-br -->`. Resolve it with `cog precommit-spell-select --languages <csv>` when the content languages are known. It has no effect on other types.

The helper's policies are `overwrite`, `skip`, and `abort` only. A merge is judgment: do it in prose with targeted edits, then use the helper for whatever safe copies remain.

## Reviewing hooks

On a stale or missing review, search for hooks relevant to the type — prefer well-maintained repos, recent releases, and official ecosystem hooks — and check every pinned repo for newer tags, archived status, or better-maintained replacements.

**Then read each pinned repo's `.pre-commit-hooks.yaml` at the tag being pinned.** A tag check alone cannot see the defects that matter most, because none of them is a version bump:

- **The id still exists and is not a legacy alias.** Upstream renames without removing (`ruff` → `ruff-check`, where bare `ruff` is marked `# Legacy alias`).
- **The upstream default `args:`.** Overriding no args means inheriting upstream's, so any comment asserting a behavior needs an explicit `args:` behind it. `typos` defaults to `[--write-changes, --force-exclude]` and therefore **auto-fixes** unless told otherwise.
- **Whether a `<id>-system` / `-docker` / `-src` variant exists**, and which one this project's environment calls for.

When updating the shared template:

- Pin release tags, never branches or `HEAD`.
- **Keep every repo's `rev:` identical across all templates that pin it** — one repo, one rev, tree-wide.
- **Prefer additive CLI flags over config-replacing ones.** Ruff's `--select` replaces the active rule selection from every resolved config file, so the project's own `select` stops applying and per-file-ignores for the dropped rules become moot; use `--extend-select`. Verify with a representative input (`ruff check --stdin-filename <path> -`), not `--show-settings`, which reports the rule as enabled either way.
- **Use upstream's `-system` id when a local binary is wanted; never override `language:` on the default id** — the override reuses the default id's `entry`, which may be an installer script rather than the binary. The choice is environment-conditional: the default id when nothing provides the binary, the `-system` id when a devShell already does.
- Preserve section order and comment style; keep the housekeeping base consistent across templates; keep `committed` the single source of truth for commit-message linting.
- Document every `language: system` hook with its external dependency, **and confirm the project's `flake.nix` actually ships a provider for each**. Such hooks get no environment and resolve off the ambient PATH.

The pre-commit internals behind these rules — `system` getting no env, `lang_base.exe_exists` rejecting `$HOME`, the `language_version: system` requirement for `node`/`golang` hooks with `additional_dependencies`, and the venv/devShell PATH-shadowing trap — are in `$(cog skill-refs path pre-commit/hook-language-resolution.md)`. Read it before changing any hook's `language`, `language_version`, or id.

## Tailoring and close

Read the repository context — README, manifests, CI, tool configs, source layout, tests — and tailor the local config: add repo-specific hooks that carry clear value, adjust args to repo conventions, add excludes only for generated, vendored, binary, external, or intentionally unmanaged paths, and tailor companions such as `lychee.toml` or `.config/nextest.toml`. Remove a hook only when it is irrelevant, obsolete, superseded, or broken beyond repair with a better replacement.

**Verified postcondition:** the config carries an `editorconfig-checker` hook consistent with the `.editorconfig` written above. When reconciling a pre-existing config that lacks it while an `.editorconfig` is present, add it rather than leaving it absent. Then validate:

```bash
pre-commit validate-config
```

Report the baseline deployed or reconciled and the alignments made; the hooks added, updated, or removed; every external tool the config now requires; and the next commands (`pre-commit install`, `pre-commit run --all-files`).

Keep all commit and push stages enforced: never recommend `SKIP=`, `--no-verify`, `git commit -n`, `pre-commit uninstall`, `core.hooksPath`, or disabling commit stages. Ask before overwriting an existing config or removing hooks someone added by hand.
