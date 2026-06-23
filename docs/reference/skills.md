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

- skills/claude/plan-one-lean-codex
- skills/claude/plan-one-lean
- skills/claude/plan-writer
- skills/claude/plan-writer-multi
- skills/claude/plan-refactor-migration
- skills/codex/plan-one-lean
- skills/codex/plan-writer
- skills/codex/plan-refactor-migration

### review-*

Code-review skills:

- skills/claude/review-lean
- skills/claude/review-findings
- skills/claude/review-loop
- skills/codex/implementation-reviewer
- skills/codex/review-lean
- skills/codex/review-findings

Plan-review sub-namespace (`review-plan-*`):

- skills/claude/review-plan-lean
- skills/codex/review-plan-lean
- .claude/skills/review-plan-implementation

### executor-*

- skills/claude/executor-lean
- skills/claude/executor-lean-codex
- skills/claude/executor-prex
- skills/claude/executor-single
- skills/claude/executor-single-codex
- skills/codex/executor-lean
- skills/codex/executor-single

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
- skills/codex/ask
- skills/codex/ast-grep
- skills/codex/gc
- skills/codex/suckless-patcher
- skills/codex/test-review
- .claude/skills/cog-skill-creator
- agents/claude/claude-delegate.md
