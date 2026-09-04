# Progressive Disclosure

> Every layer of a skill package has a different cost. Put each fact in the layer that matches how often the agent needs it.

## The cost model

| Layer           | Loaded                             | Cost              |
| --------------- | ---------------------------------- | ----------------- |
| `description`   | Always, for every installed skill  | Highest           |
| `SKILL.md` body | On every invocation of this skill  | High              |
| `references/`   | Only when the body says to read it | Low               |
| `scripts/`      | Only when executed                 | None at load time |

The description is read even when the skill never fires. The body is read even when the run uses one paragraph of it. A reference costs nothing until the agent needs it.

## Placement rules

**`description`** carries routing facts only. What the skill produces, when to use it, and the boundary against a sibling skill. Nothing else.

**`SKILL.md`** carries what the agent needs on every invocation:

- The workflow, in order.
- The decisions the agent must make, and how to make them.
- The safety rules that bound the run.
- The commands the skill invokes.
- Pointers to the references, and the condition for reading each one.

**`references/`** carries material needed on some runs but not all:

- A large table the agent consults for one case.
- A per-language, per-format, or per-platform variant.
- A worked example longer than a few lines.
- A specification the agent quotes rather than paraphrases.

**`scripts/`** carries deterministic routines. See [script-extraction.md](./script-extraction.md).

**`assets/`** carries files the skill copies into the user's project, such as a template or a starter configuration.

## The deletion test

Apply this to every paragraph of the body:

> If I delete this paragraph, does the agent make a likely task error?

- Yes → keep it in the body.
- Only on some runs → move it to a reference and point at it.
- No → delete it.

Most first drafts fail this test in the same three ways.

## What to delete

**Facts a capable agent already knows.** Do not explain what JSON is, how a for loop works, or what a git branch means. Write the constraint that is specific to this task.

**Restated rules.** When a reference owns a rule, point at the reference. Do not summarize it in the body, because the summary drifts from the owner and the reader cannot tell which one is current.

**Reassurance.** Text that tells the agent the task matters changes no behavior.

**Preemptive scoping.** A list of what the skill is not usually belongs in the description as one boundary clause, or nowhere.

## Pointing at a reference

State the condition and the path together, so the agent knows when to spend the read:

```markdown
For a Rust project, read `references/rust.md` before you edit the manifest.
```

Do not write "see the references directory for more information". That gives the agent no condition, so it either always reads or never reads.

## Depth

Keep the package one level deep. The body points at a reference. A reference does not point at another reference.

A chain of references costs the agent one read per hop and hides the real owner of a rule. When two references need the same fact, that fact has one owner and both point at it, or the two references merge.
