---
name: bootstrap-governance
description: >
  Seed a project's governance docs: an AGENTS.md carrying the self-containment
  principle and a thin CLAUDE.md that imports it. Use when the user says
  "bootstrap-governance", "governance docs", "seed CLAUDE.md", "seed AGENTS.md",
  or "self-containment docs".
model: opus
effort: low
---

<!-- trigger-tests: "bootstrap-governance", "governance docs", "seed CLAUDE.md", "seed AGENTS.md", "self-containment docs" -->

# Bootstrap governance docs

Establish the project's baseline governance: an `AGENTS.md` and a thin `CLAUDE.md` that imports it with `@AGENTS.md`.

**Governance content has exactly one home: `AGENTS.md`.** It is read by both Claude Code — through the `CLAUDE.md` pointer — and the `AGENTS.md`-native tools, so `CLAUDE.md` stays a byte-exact thin pointer and nothing is duplicated across the two. `cog bootstrap-audit` verifies that pointer deterministically.

`AGENTS.md` encodes the **self-containment principle**: the project holds the knowledge it depends on in-repo, and an external reference is allowed only as a public link or citation, never as a load-bearing internal dependency. Tailoring adapts the docs to the project; it never removes that principle.

Follow the shared routine at `$(cog skill-refs path bootstrap/domain-worker-routine.md)`; the freshness type is always `generic`:

```bash
cog bootstrap-template-review check --domain governance --type generic --json
```

A fresh review means reuse the cached `summary`; stale or missing means research current governance-doc conventions (the CLAUDE.md/AGENTS.md format), update `skill-refs/templates/governance/` when justified, and `stamp` before reconciling.

## Deploy

```bash
cog governance-detect --json
cog governance-apply --conflict "$POLICY" --json
```

Root `CLAUDE.md` and `AGENTS.md` stay at the repository root for every project type.

This skill is the single writer of that tree. For a project that already carries any of these docs, reconcile in prose: apply the missing pieces and preserve the operator's existing content.

## Tailor

Fill `{{PROJECT_NAME}}` in `AGENTS.md` and adapt its working conventions to the actual stack and task runner.

Two things survive tailoring unchanged: `AGENTS.md` keeps the `self-contained` non-negotiable line, which is what the audit's content requirement checks, and `CLAUDE.md` stays the byte-exact thin `@AGENTS.md` pointer.

Report the docs established or reconciled and any template paths updated.
