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

Skill-source references required at runtime live in the packaged `skill-refs/` tree. Skills should
resolve those references with `cog skill-refs path <rel>`, which checks the XDG-installed
`$XDG_DATA_HOME/cog/skill-refs` tree first and then falls back to the repo checkout. External
docs-n-notes references are optional enhancers only and must degrade gracefully when absent.

Codex-spawning Claude skills must use the wrapper documented in
[Codex single entrypoint](codex-single-entrypoint.md).

## Taxonomy Inventory

The governing skill taxonomy is defined in
[Skill contract](skill-contract.md) ("Prefix taxonomy") and
[ADR-0016](../decisions/0016-skill-prefix-taxonomy.md). `cog skill-lint` enforces it with the
`skill-prefix-taxonomy` rule. The filesystem remains the inventory source of truth; the listing
below maps each currently shipped artifact to its taxonomy class.

### plan-*

- skills/claude/plan-claude
- skills/claude/plan-writer
- skills/claude/plan-writer-multi
- skills/claude/refactor-migration-plan
- skills/codex/plan-codex
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

- skills/claude/review-plan-claude
- skills/codex/review-plan-codex
- .claude/skills/review-implementation-plans

### executor-*

- skills/claude/executor-claude
- skills/claude/executor-prex
- skills/codex/executor-codex-session
- skills/claude/prex — temporary compatibility alias for `/prex`; carries
  `<!-- cog-skill: superseded-by executor-prex -->`

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

These compatibility notes record rename transitions that are still visible in shipped skill names or
queue prompts.

- `prex` -> `executor-prex` has landed as the canonical executor skill. The `/prex` skill remains a
  first-class compatibility alias during the transition, and existing `/prex` queue prompts remain
  supported instead of being migrated in Round 1 of `executor-prex-refactor`.
- `plan-reviewer` is retained as a legacy compatibility shim and carries
  `<!-- cog-skill: superseded-by review-plan-claude -->`. New plan-review work uses
  `review-plan-claude` or `review-plan-codex`.
- `runner-queue` already satisfies the taxonomy as a `runner-*` skill; no rename planned.
