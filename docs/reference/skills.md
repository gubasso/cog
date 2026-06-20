# Skills

`cog` ships runtime-specific skill and agent trees. The filesystem is the inventory source of truth;
this reference describes the layout by pattern.

## Claude

Claude skills live under:

```text
skills/claude/*/SKILL.md
```

Claude agents live under:

```text
agents/claude/*.md
```

`agents/claude/claude-delegate.md` is the reusable foreground delegation primitive used by
orchestration skills that need isolated execution and nested subagents.

## Codex

Codex skills live under:

```text
skills/codex/*/SKILL.md
```

The Codex tree is smaller than the Claude tree because Codex and Claude expose different skill and
tool surfaces. Keep instructions runtime-native instead of forcing one shared skill body to cover
both systems.

## Project-Local Authoring Skill

The repo-local authoring skill lives under:

```text
.claude/skills/cog-skill-creator/SKILL.md
```

This skill is for maintaining this repository's shipped skill trees. It is not copied by
`install.sh`, which only installs payload skills from `skills/claude/` and `skills/codex/`.

Skill authoring and lint rules are defined in [Skill contract](skill-contract.md).

## Reference Resolution

Skill docs may point to docs-n-notes references and should use progressive disclosure: load the
relevant reference only when the task needs it. This project documents cog itself; it does not copy
or rewrite the external reference shelves into shipped skill bodies.

Codex-spawning Claude skills must use the wrapper documented in
[Codex single entrypoint](codex-single-entrypoint.md).

## Taxonomy Inventory

The governing skill taxonomy is defined in
[Skill contract](skill-contract.md) ("Prefix taxonomy") and
[ADR-0016](../decisions/0016-skill-prefix-taxonomy.md). `cog skill-lint` enforces it with the
`skill-prefix-taxonomy` rule. The filesystem remains the inventory source of truth; the listing
below maps each currently shipped artifact to its taxonomy class.

### plan-*

- skills/claude/plan-writer
- skills/claude/plan-writer-multi
- skills/claude/refactor-migration-plan
- skills/codex/plan-writer
- skills/codex/refactor-migration-plan

### review-*

Code-review skills:

- skills/claude/review-code-deep
- skills/claude/review-findings
- skills/claude/review-loop
- skills/codex/implementation-reviewer
- skills/codex/review-code-deep

Plan-review sub-namespace (`review-plan-*`):

- skills/claude/plan-reviewer
- .claude/skills/review-implementation-plans

### executor-*

- skills/claude/prex

### runner-*

- skills/claude/runner-queue

### Other shipped skills and agents

Utility skills outside the four governed behavioral prefixes, plus shipped agents:

- skills/claude/ask
- skills/claude/ast-grep
- skills/claude/claudemd
- skills/claude/gc
- skills/claude/osc-obs
- skills/claude/pre-commit
- skills/claude/suckless-patcher
- skills/claude/test-review
- skills/claude/tsk-impl
- skills/claude/tsk-new
- skills/codex/ask
- skills/codex/ast-grep
- skills/codex/gc
- skills/codex/suckless-patcher
- skills/codex/test-review
- .claude/skills/cog-skill-creator
- agents/claude/claude-delegate.md

## Taxonomy Migration Notes

These are planned renames recorded for traceability; the renames themselves are owned by dependent
sibling plans and are out of scope here.

- `prex` -> `executor-prex` (owned by the `executor-prex-refactor` plan).
- `plan-reviewer` -> `review-plan-claude` (owned by the `lean-plan-and-review-skills` plan). Its
  `SKILL.md` currently carries a stale `<!-- cog-skill: superseded-by review-plan-reviewer -->`
  marker; that marker is rewritten to `review-plan-claude` when the rename lands in
  `lean-plan-and-review-skills`. The planned target above is authoritative.
- `runner-queue` already satisfies the taxonomy as a `runner-*` skill; no rename planned.
