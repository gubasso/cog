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
.claude/skills/skill-builder/SKILL.md
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
