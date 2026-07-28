---
name: bootstrap-knowledge-base
description: >
  Scaffolds a knowledge-base project's own architecture for the current project: the
  content-library conventions, a lean _docs/ metadata/specs scaffold (the product-versus-metadata
  relationship, Diataxis zones, review checklist), and the per-area AGENTS.md digest
  standard. Delegates deterministic markdown/KB detection and template copying to the cog
  CLI while keeping content-structure and digest judgment in prose. Use when the user says
  "bootstrap-knowledge-base", "knowledge base project", "set up a knowledge base", "_docs
  specs scaffold", or "AGENTS.md digests".
model: opus
effort: low
---

<!-- trigger-tests: "bootstrap-knowledge-base", "knowledge base project", "set up a knowledge base", "AGENTS.md digests" -->

# Bootstrap Knowledge-Base Skill

Scaffold the architecture of a knowledge-base project for the current repository: a library of knowledge organized as directories and markdown files. In a knowledge base the product is the knowledge itself — the content tree — so this skill establishes the conventions that keep that product coherent and the `_docs/` metadata/specs namespace that describes it.

Principle: the content tree is the product; `_docs/` is the one specially-marked metadata/specs namespace about that product, exactly as a code project's `docs/` describes its code. A bare root `docs/` directory in a knowledge base is likely library content and must be inspected before treating it as scaffold metadata. Every substantial content area carries an `AGENTS.md` digest — a current map of that area, loaded first, derived from its files, never the source of truth.

## Boundary

This skill owns the knowledge-base content architecture: the content-library conventions, the lean `_docs/` metadata/specs scaffold (`guides/`, `reference/`, `explanation/`, the docs index, the documentation conventions and review checklist), and the per-area content-digest `AGENTS.md` standard.

It defers to peer domains as structural contracts, never authoring their files:

- The root `CLAUDE.md`, the root author-instructions `AGENTS.md`, and the `_docs/decisions/` ADR scaffold (template plus seed ADR) belong to the governance domain.
- Pre-commit hooks — markdown lint, formatting, link and spell checking — belong to the pre-commit domain, auto-targeted at the markdown template. The spell checker is language-dependent: this skill determines the knowledge base's content languages (a judgment it owns) and declares them so the pre-commit domain selects the matching variant — `typos` for English-only, `cspell` for content that includes a non-English language.
- `.editorconfig` content belongs to the editorconfig domain.
- `.gitignore` (including the `.draft/` ignore), `LICENSE`, and `README` belong to the repo domain.

The per-area `AGENTS.md` digests this skill owns are content maps carrying `digest-of` frontmatter; they are distinct from the single root author-instructions `AGENTS.md` the governance domain owns.

## Inputs

- `$ARGUMENTS`: optional scaffold type; the knowledge-base scaffold ships as `markdown`.
- Template directory: cog's `skill-refs/templates/knowledge-base/` tree, or a caller-supplied `--template-root`.
- Reference canon: `$(cog skill-refs path knowledge-base/docs-design.md)` — the documentation-design principles this skill tailors from.
- Current working directory: the target project.

## Cog Contract

`cog` must be installed and on `PATH`; a bare call fails legibly if it is missing. Detect the scaffold type when the user did not provide one:

```bash
cog kb-detect --json
```

Detection resolves `markdown` when the repository is a markdown content library (markdown dominates and no code language is present). If detection reports no match, ask the user to confirm the project is a knowledge base, then rerun with an explicit type:

```bash
cog kb-detect --type "$TYPE" --json
```

The detection helper emits `{ok, project_root, template_root, requested_type, detected_type,
confidence, classification, signals, conflicts, template_dir, template_config, template_exists,
reason}`, anchored on the scaffold's `_docs/README.md`.

Deploy the scaffold after conflict policy is explicit:

```bash
cog kb-apply --type "$TYPE" --conflict "$KB_POLICY" --json
```

`kb-apply` copies the scaffold tree under `<project>/` and emits `{ok, type, template_dir, copied[], skipped[], conflicts[], conflict, reason}`. Its `--conflict` policy is `overwrite`, `skip`, or `abort` (default `abort`). Reconciling a project that already carries some `_docs/` structure is judgment that stays in this skill: inspect the existing files and merge in prose rather than blind-overwriting metadata the project already tuned. A pre-existing bare `docs/` tree is likely library content in a knowledge base; inspect it before deciding whether any of it belongs in `_docs/`.

## Template refresh

Follow the shared refresh routine at `$(cog skill-refs path bootstrap/template-refresh-routine.md)` on every run: check freshness, review and update the shared template when stale or missing, stamp the review, then reconcile the target — installing when absent, aligning improvements when present. Use the freshness `check` JSON `/bootstrap` supplied in the brief; when it is absent, resolve the type with `kb-detect` and run it yourself:

```bash
cog bootstrap-template-review check --domain knowledge-base --type "$TYPE" --json
```

When `review.fresh` is `true`, reuse the cached `summary` and skip the spec research — go straight to deploying and tailoring the scaffold in the Workflow below. When it is `stale` or `missing`, do the docs-design research (step 4), update `skill-refs/templates/knowledge-base/<type>/` when justified, then stamp the review with `cog bootstrap-template-review stamp --domain knowledge-base --type "$TYPE"
...` — even when the conclusion is "no template change" — before reconciling the project scaffold. `stamp` fails fast when the template SoT is not writable; surface that.

## Workflow

1. Resolve scaffold type. If `$ARGUMENTS` provides a type, run `kb-detect --type "$TYPE"` to validate the template path. Otherwise run `kb-detect --json`.

2. If detection reports no match, confirm with the user that the repository is a knowledge base rather than a code project. Do not scaffold a KB over a code project on a weak signal.

3. If the template root is missing, stop and report the helper's reason.

4. Read `$(cog skill-refs path knowledge-base/docs-design.md)` for the documentation-design canon. Optionally web-search current Diataxis and documentation guidance (`diataxis.fr`) as an enhancer; proceed from the canon and this prose when offline.

5. Establish the scaffold. Deploy the template with `cog kb-apply`, reconciling a pre-existing `_docs/` in prose rather than overwriting it. Treat a bare `docs/` tree as likely library content until inspection proves otherwise.

6. Tailor to the project's knowledge:
   - map the existing top-level content directories to the content-library conventions, and describe the product-versus-metadata boundary in the deployed `_docs/explanation/knowledge-base-architecture.md` using the repository's real subject areas;
   - seed the per-area `AGENTS.md` digest standard: copy `_docs/reference/agents-digest-template.md` into each substantial content area as its `AGENTS.md`, fill the `digest-of`/`last-synced`/`source-files`/`token-estimate` frontmatter, and summarize the area from its files;
   - point the docs index and conventions at the peer domains that own the rest (governance for the root author-instructions and `_docs/decisions/`, pre-commit for markdown tooling, repo for the `.draft/` gitignore), without authoring their files here.

7. Determine the knowledge base's content languages from its material and the user, then resolve the spell-checker variant to carry into the pre-commit follow-up:

   ```bash
   cog precommit-spell-select --languages "$LANGUAGES" --json
   ```

   English-only content resolves to `typos`; content with any non-English language resolves to `cspell`. Record the resolved `spell` value in the summary so the pre-commit domain applies the matching variant.

8. Present a final summary: the scaffold deployed or reconciled, the content-library conventions mapped to the project's real areas, the `AGENTS.md` digests seeded, the declared content languages and resolved spell variant, and the peer domains a follow-up run should invoke (governance, pre-commit, editorconfig, repo).

## Guardrails

- Keep each durable fact in one owning home; the deployed docs are an index-and-conventions layer, not a second copy of the knowledge.
- Reconcile a pre-existing `_docs/` in prose; ask before overwriting metadata the project already tuned. Inspect a bare root `docs/` tree as likely library content before moving or rewriting it.
- Treat helper output as mechanics only. Content-structure and digest decisions remain skill judgment.
- Author no peer-domain files: root `CLAUDE.md`/`AGENTS.md`, `_docs/decisions/`, hooks, `.editorconfig`, `.gitignore`, `LICENSE`, and `README` stay with their own domains.
