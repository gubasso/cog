# Descriptions and Triggers

> The description is a routing interface, not a summary. The agent reads it to decide whether to load the skill at all.

## What the description is for

An agent sees every installed skill's name and description at once. It sees no body. The description is therefore the only evidence the agent has when it decides to load your skill.

A description that explains what the skill does answers the wrong question. Write what the user was trying to do.

## Required shape

State the trigger directly:

```yaml
description: >
  Convert a spreadsheet into a normalized CSV, with column types inferred and
  reported. Use when the user says "clean this spreadsheet", "normalize the
  columns", or hands over an .xlsx file and asks for CSV.
```

Three parts carry the routing:

1. **What the skill produces.** One clause, in the user's words.
2. **When to use it.** The literal phrasings a user types.
3. **The boundary.** The nearby case this skill does not cover, when a nearby case exists.

## Rules

- Write user intent, not implementation. "Use when the user asks to clean a spreadsheet" routes. "Uses pandas to coerce dtypes" does not.
- Include the words a user actually types, including the informal ones.
- Name the boundary when a sibling skill is close. Ambiguity between two skills costs more than a missing skill.
- Keep the description within the length the runtime accepts. Runtimes differ, so verify the limit for each runtime you target.
- Do not describe the skill's internal steps. The body carries those.

## Trigger fixtures

A description is a claim about routing. Test the claim.

Write three case classes for every skill:

| Class     | Meaning                                        | Expected         |
| --------- | ---------------------------------------------- | ---------------- |
| Positive  | A prompt the skill must handle                 | Triggers         |
| Negative  | A prompt about a different task                | Does not trigger |
| Near-miss | A prompt that shares vocabulary but not intent | Does not trigger |

Near-miss cases carry the most information. A skill for cleaning spreadsheets must not fire on "write a spreadsheet formula", even though both prompts say "spreadsheet".

Write realistic prompts. Vary the phrasing. Include one terse prompt and one long, detailed prompt for every case class.

## Fixture shape

```yaml
cases:
  - id: clean-xlsx-plain
    prompt: "can you clean up this spreadsheet for me"
    triggers: true
    class: positive

  - id: formula-help
    prompt: "help me write a spreadsheet formula for a running total"
    triggers: false
    class: near-miss

  - id: unrelated-git
    prompt: "rebase my branch onto main"
    triggers: false
    class: negative
```

## Optimizing a description

Routing is probabilistic. A single successful run proves nothing.

- Run each case several times and record the pass rate.
- Split the cases into a train set and a validation set before you tune.
- Tune the wording against the train set only.
- Report the final rate on the validation set.

When you tune against every case you have, you learn the cases, not the routing.
