---
name: bootstrap-governance
description: >
  Seeds a project's governance docs - a CLAUDE.md, an AGENTS.md, and a docs/decisions/ ADR
  scaffold (MADR-minimal template plus a seed self-containment ADR) - encoding the
  self-containment principle, while delegating deterministic detection, template copying, and
  freshness review to the cog CLI and keeping tailoring in prose. Use when the user says
  "governance docs", "seed CLAUDE.md", "seed AGENTS.md", "self-containment docs", or "ADR scaffold".
model: opus
effort: low
---

<!-- trigger-tests: "governance docs", "seed CLAUDE.md", "seed AGENTS.md", "self-containment docs", "ADR scaffold" -->

# Bootstrap Governance Skill

Establish a project's baseline governance docs: an `AGENTS.md`, a thin `CLAUDE.md` that imports it
with `@AGENTS.md`, and a `docs/decisions/` ADR scaffold (a MADR-minimal `template.md` plus a seed
`0001-self-containment.md`). `AGENTS.md` is the single source of truth — read by both Claude Code
(through the `CLAUDE.md` pointer) and the `AGENTS.md`-native tools — and it encodes the
**self-containment principle**: the project holds the knowledge it depends on in-repo, and an external
reference is allowed only as a public link or citation, never as a load-bearing internal dependency.
Deterministic detection, copying, and freshness review run through cog; per-project tailoring stays
judgment.

Principle: templates are broad and general; the project files are precise and tailored — the seeded
docs are adapted to the actual project, and the self-containment principle is preserved through the
tailoring. Governance content has one home: `AGENTS.md`. `CLAUDE.md` stays a thin `@AGENTS.md`
pointer so nothing is duplicated across the two files.

## Inputs

- Current working directory: the target project.
- Template tree: cog's `skill-refs/templates/governance/` (`CLAUDE.md`, `AGENTS.md`,
  `docs/decisions/template.md`, `docs/decisions/0001-self-containment.md`), or a caller-supplied
  `--template-root`.
- The project name and stack, used to tailor the seeded docs.

## Cog Contract

`cog` must be installed and on `PATH`; a bare call fails legibly if it is missing.

Detect the present governance docs and the template type:

```bash
cog governance-detect --json
```

It reports `detected_type` (`generic`), a `present` boolean (both `CLAUDE.md` and `AGENTS.md` exist),
and the per-artifact `artifacts[]` breakdown. Use the detector findings the orchestrator supplied in
the brief; when absent, run it yourself.

Deploy the governance docs as the single writer of that tree. Copy the files under an explicit
conflict policy:

```bash
cog governance-apply --conflict "$POLICY" --json
```

It copies the thin `CLAUDE.md` pointer, `AGENTS.md`, and the `docs/decisions/` ADR scaffold,
preserving layout, and emits `{ok, copied, skipped, conflicts, conflict, reason}`; treat that output
as mechanics only.

## Template refresh

Follow the shared refresh routine at `$(cog skill-refs path bootstrap/template-refresh-routine.md)` on
every run: check freshness, review and update the shared templates when stale or missing, stamp the
review, then reconcile the target — installing when absent, applying improvements when present. The
freshness type is `generic`. Use the freshness `check` JSON `/bootstrap` supplied in the brief; when it
is absent, run it yourself:

```bash
cog bootstrap-template-review check --domain governance --type generic --json
```

When `review.fresh` is `true`, reuse the cached `summary` and skip the research — go straight to
reconcile in the Workflow below. When it is `stale` or `missing`, web-research current governance-doc
and ADR conventions (MADR, the CLAUDE.md/AGENTS.md format), update the
`skill-refs/templates/governance/` tree when justified, then stamp the review with `cog
bootstrap-template-review stamp --domain governance --type generic ...` — even when the conclusion is
"no template change" — before reconciling the project docs. `stamp` fails fast when the template SoT is
not writable; surface that.

## Workflow

1. Resolve the present state with `cog governance-detect --json` (or the brief's detector findings).

2. Deploy the governance docs as their single writer. For a new project, copy under an explicit
   conflict policy. For a project that already carries any of these docs, reconcile in prose rather
   than overwriting: apply the missing pieces and preserve the operator's existing content.

3. Tailor the deployed docs to the project: fill `{{PROJECT_NAME}}` in `AGENTS.md`, adapt its working
   conventions to the actual stack and task runner, and adjust the seed ADR when the project already
   uses `docs/decisions/` numbering. Keep the self-containment principle intact — `AGENTS.md` retains
   the `self-contained` non-negotiable so the audit's content requirement passes — and leave
   `CLAUDE.md` as the thin `@AGENTS.md` pointer so governance stays single-sourced.

4. Web-research current governance-doc and ADR conventions as enhancers, and fold worthwhile
   additions into the deployed files.

5. Present a final summary: the docs established or reconciled, the ADR scaffold seeded, and any
   template paths updated.

## Guardrails

- Own `CLAUDE.md`, `AGENTS.md`, and the `docs/decisions/` seed as the single writer of that tree.
- Reconcile a pre-existing governance doc with the operator's content rather than overwriting it
  silently; renumber a colliding seed ADR instead of clobbering an existing one.
- Preserve the self-containment principle through tailoring: `AGENTS.md` keeps the `self-contained`
  non-negotiable line, and `CLAUDE.md` stays the thin `@AGENTS.md` pointer.
- Treat helper output as mechanics only. Tailoring and reconciliation remain judgment.
- Deterministic mechanics stay behind `cog`; do not run git commands.
