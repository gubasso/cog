# Skill Authoring Standard

> The entry point for authoring an Agent Skill. This standard is universal. It states how to manufacture a good skill for any agent runtime, and it names no CLI, no framework, and no repository layout.

## The central rule

A skill has one authored owner. Sequencing and judgment live in `SKILL.md`. Durable knowledge lives in a reference file the package owns. Deterministic mechanics live in a script or a command.

A rule has one owner. When two documents state the same rule, one of them is wrong and nobody knows which.

## What a skill is

A skill is a set of instructions an agent loads when a user's intent matches its description. The agent reads the whole body on every invocation, so every paragraph costs tokens each time the skill fires.

A skill is not documentation. Documentation explains a system to a reader. A skill changes what an agent does.

Apply this test to every paragraph you write:

> If I delete this paragraph, does the agent make a likely task error?

Keep the paragraph when the answer is yes. Delete it when the answer is no.

## Package shape

```text
<skill-name>/
├── SKILL.md          instructions loaded on every invocation
├── references/       supporting material loaded on demand
├── scripts/          deterministic routines the skill calls
└── assets/           files the skill copies or reads
```

`SKILL.md` opens with YAML frontmatter. Two fields are required:

```yaml
---
name: <skill-name>
description: <when to use this skill>
---
```

The directory name and the `name` field must match. The name uses lowercase letters, digits, and hyphens.

## Authoring phases

Work through these phases in order. Do not skip a phase because the skill looks small.

1. **Observe the need.** Name the task a user repeats and the errors an agent makes without help.
2. **Define the trigger.** Write the description first. See [descriptions-and-triggers.md](./descriptions-and-triggers.md).
3. **Choose the placement.** Decide what belongs in the description, the body, and a reference. See [progressive-disclosure.md](./progressive-disclosure.md).
4. **Extract the mechanics.** Decide what becomes a script. See [script-extraction.md](./script-extraction.md).
5. **Draft.** Write the body under [writing-style.md](./writing-style.md).
6. **Bound the effects.** Apply [security.md](./security.md).
7. **Evaluate.** Build the fixtures in [evaluations.md](./evaluations.md).
8. **Close.** Walk [checklist.md](./checklist.md).

## Self-containment

A skill package carries everything it needs to run. It reads its own `references/` by a path relative to the skill directory. It does not depend on a knowledge repository the user does not have.

An external URL is further reading. When the agent cannot reach it, the skill must still work.

A skill that requires a tool must say so, must check for the tool, and must fail with a legible message when the tool is absent.

## Definition of done

- The frontmatter carries a valid `name` and a description that states when to use the skill.
- The directory name matches the `name` field.
- Every paragraph in the body survives the deletion test.
- Every load-bearing reference resolves inside the package.
- Every deterministic routine is a script or a command, not inline prose the model retypes.
- Trigger fixtures cover positive, negative, and near-miss cases.
- A behavior fixture states what a successful run produces.
- The skill runs on a machine that carries only the tools the skill declares.
