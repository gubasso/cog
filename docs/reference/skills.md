# Skills

`cog` ships skill and agent trees in two source classes. The filesystem is the inventory source of truth; this reference describes the layout by pattern.

## Portable

A portable skill has one authored owner and installs the same bytes into every supported agent root:

```text
skills/*/SKILL.md
```

Portable is the default class. A portable package declares only the upstream Agent Skills required pair, `name` and `description`, because that is the intersection of every target runtime's allowlist. It invokes no `cog` command, so it runs in a project that never installed cog.

`skills/skill-creator` is the shipped skill-authoring product. It carries the universal authoring standard as byte-identical copies under its own `references/`, and `cog skill-vendor check` fails when a copy drifts from its owner at `skill-refs/skill-authoring/universal/`.

## Claude

Claude skills live under:

```text
skills-native/claude/*/SKILL.md
```

Claude agents live under:

```text
agents/claude/*.md
```

`agents/claude/claude-delegate.md` is the reusable foreground delegation primitive used by orchestration skills that need isolated execution and nested subagents.

## Codex

Codex skills live under:

```text
skills-native/codex/*/SKILL.md
```

The Codex tree is smaller than the Claude tree because Codex and Claude expose different skill and tool surfaces. Keep instructions runtime-native instead of forcing one shared skill body to cover both systems.

## Authoring a skill in this repository

There is no in-repo skill that authors cog skills. The rules are the authority, and the gates enforce them.

Read [`skill-refs/skill-authoring/universal/standard.md`](../../skill-refs/skill-authoring/universal/standard.md) for the manufacturing standard, [Skill contract](./skill-contract.md) for cog house policy, and [`skill-refs/skill-authoring/universal/checklist.md`](../../skill-refs/skill-authoring/universal/checklist.md) before you present the work. `cog skill-lint` enforces the mechanically decidable parts through pre-commit.

One name never exists in both source classes. `install.sh` fails closed before its first destination write when it does.

## Reference Resolution

This applies to native skills. A portable package under `skills/` carries its references inside its own package directory and resolves them relative to the skill, because it invokes no `cog` command.

Skill-source references required at runtime by a native skill live in the packaged `skill-refs/` tree. A native skill resolves those references with `cog skill-refs path <rel>`, which checks the XDG-installed `$XDG_DATA_HOME/cog/skill-refs` tree first and then falls back to the repo checkout. Every load-bearing reference ships in-repo; public online docs are welcome only as optional further reading and must degrade gracefully when absent. See [ADR-0008](../decisions/ADR-0008-self-contained-resource-homes.md).

Codex-spawning Claude skills use the durable wrapper documented in the [orchestration contract](./orchestration-contract.md).

## Taxonomy Inventory

The governing skill taxonomy is defined in [Skill contract](./skill-contract.md) ("Prefix taxonomy") and [ADR-0006](../decisions/ADR-0006-runtime-skill-trees-and-taxonomy.md). `cog skill-lint` enforces it with the `skill-prefix-taxonomy` rule. The filesystem remains the inventory source of truth; the listing below maps each currently shipped artifact to its taxonomy class.

### plan-*

- skills-native/claude/plan-oneshot-codex
- skills-native/claude/plan-oneshot
- skills-native/claude/plan-multi
- skills-native/codex/plan-oneshot

### review-*

Code-review skills:

- skills-native/claude/review-oneshot
- skills-native/claude/review-findings
- skills-native/claude/review-loop
- skills-native/claude/review-loop-gc
- skills-native/codex/implementation-reviewer
- skills-native/codex/review-oneshot
- skills-native/codex/review-findings

Plan-review sub-namespace (`review-plan-*`):

- skills-native/claude/review-plan-oneshot
- skills-native/claude/review-plan-oneshot-codex
- skills-native/claude/review-plan-multi
- skills-native/codex/review-plan-oneshot

`plan-*` skills emit self-contained plan-docs. `review-plan-*` skills emit annotated reviews that remain separate audit artifacts. A plan-naming consumer validates the base and review, retains the review, then folds them before implementation. Executor-prex uses `plan-review.md` plus `vetted-plan.md` and sibling `vetted-plan-review-items.json`, `vetted-plan-fold-manifest.json`, and `vetted-plan-fold-check.json`. Executor-oneshot, executor-oneshot-codex, and plan-vetted use `prepared-plan-review.md` plus `prepared-plan.md` and the corresponding `prepared-plan-*` proof files.

### executor-*

- skills-native/claude/executor-vetted
- skills-native/claude/executor-prex
- skills-native/claude/executor-oneshot
- skills-native/claude/executor-oneshot-codex
- skills-native/codex/executor-oneshot

`executor-vetted` is a Claude-only orchestrator (its `plan-multi` / `review-plan-multi` producers run Claude and Codex together), so it has no Codex twin or `-codex` delegation launcher.

### Other shipped skills and agents

Utility skills outside the three governed behavioral prefixes, plus shipped agents:

- skills-native/claude/assess-input
- skills-native/codex/assess-input
- skills-native/claude/ask
- skills-native/claude/ast-grep
- skills-native/claude/claudemd
- skills-native/claude/gc
- skills-native/claude/gc-repo
- skills-native/claude/osc-obs
- skills-native/claude/bootstrap
- skills-native/claude/bootstrap-lint
- skills-native/claude/bootstrap-nix
- skills-native/claude/bootstrap-repo
- skills-native/claude/bootstrap-governance
- skills-native/claude/bootstrap-ci
- skills-native/claude/bootstrap-taskrunner
- skills-native/claude/bootstrap-rust
- skills-native/claude/bootstrap-installer
- skills-native/claude/suckless-patcher
- skills-native/claude/test-review
- skills-native/codex/ask
- skills-native/codex/ast-grep
- skills-native/codex/suckless-patcher
- skills-native/codex/test-review
- skills/skill-creator
- agents/claude/claude-delegate.md
