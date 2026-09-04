---
name: skill-creator
description: >
  Author a new Agent Skill package, or revise an existing one, against a
  self-contained manufacturing standard: routing description, progressive
  disclosure, controlled prose, script extraction, safety bounds, and
  evaluation fixtures. Works in any project and depends on no CLI beyond the
  tools the drafted skill itself declares. Use when the user says "create a
  skill", "new skill", "author a skill", "scaffold a skill", "write a SKILL.md",
  or asks to review or improve a skill they already have. Not for invoking an
  existing skill, and not for writing ordinary project documentation.
---

<!-- trigger-tests: "create a skill", "new skill", "author a skill", "write a SKILL.md", "improve this skill" -->

# Skill Creator

Author a skill package that another agent can load and act on. This skill owns the interview, the drafting judgment, and the approval gate. The standard it applies lives in this package, under `references/`.

## Scope

Produce a complete package: `SKILL.md`, any `references/`, `scripts/`, and `assets/` the skill needs, and the evaluation fixtures that test it.

The output is self-contained. A skill this skill writes runs on a machine that carries only the tools that skill declares.

## References

All of these live inside this package. Resolve each one relative to this file, and read it at the point the workflow calls for it.

| File                                      | Read it when                                         |
| ----------------------------------------- | ---------------------------------------------------- |
| `references/standard.md`                  | Always, before the interview                         |
| `references/descriptions-and-triggers.md` | Writing or revising the description                  |
| `references/progressive-disclosure.md`    | Deciding what goes in the body                       |
| `references/writing-style.md`             | Drafting or rewriting prose                          |
| `references/script-extraction.md`         | Any deterministic routine appears                    |
| `references/security.md`                  | The skill reads outside content, or changes anything |
| `references/evaluations.md`               | Building the fixtures                                |
| `references/checklist.md`                 | Before presenting the draft                          |

## Workflow

1. Read `references/standard.md`.

2. Parse the request for a name, a purpose, and a target runtime. Ask only for what is missing.

3. If the intent is vague, stop and ask. Do not infer the purpose from the name alone.

4. Decide the mode, and say which one you chose:
   - **Create** when the request asks for a new skill.
   - **Revise** when the request names a skill that already exists, or asks to review, fix, or improve one.

   If the request is a create but a skill with that name already exists, stop and report the collision. Ask whether to revise that skill or to choose another name. Never overwrite an existing skill under a create.

   If the request is a revise but no such skill exists, stop and report that. Ask whether to create it.

5. Interview for intent. In revise mode, read the existing package first, then ask only about what the request changes. Cover every item:
   - The task the user repeats, and the errors an agent makes without help.
   - The phrasings a user types when they want this skill.
   - The nearest sibling skill, and the boundary against it.
   - Inputs, outputs, and the artifacts the run produces.
   - Side effects: what it writes, what it deletes, what it sends.
   - Preflight state the skill must check before it acts.
   - The tools it requires, and which are hard and which are soft.
   - The failures it must handle, and what it does on each.

6. Write the description first, under `references/descriptions-and-triggers.md`. The description is the routing interface, so it is drafted before the body, not after.

7. Run the extraction interview, under `references/script-extraction.md`:
   - List every deterministic routine the skill needs.
   - Split each judgment-tangled routine at its seam.
   - Decide, for each, script or prose. Record the reason.
   - Keep trivial one-liners inline.

8. Place each fact, under `references/progressive-disclosure.md`. Apply the deletion test to every paragraph you intend to keep.

9. Draft the body under `references/writing-style.md`.

10. Apply `references/security.md` when the skill reads outside content, requests tools, or changes anything.

11. Draft the fixtures under `references/evaluations.md`. Trigger fixtures carry positive, negative, and near-miss cases. A behavior fixture states the expected artifacts and the deterministic assertions.

12. If the drafted skill needs any of the standard this package carries, copy the file it needs into the drafted skill's own `references/`. The drafted package must not read this package.

13. Walk `references/checklist.md`. Fix every item that fails.

14. Present the complete proposed tree. Show one fenced block per file, labeled with its path relative to the skill directory. State where the package will be written.

    In revise mode, show only the files that change, and mark each one `new`, `changed`, or `removed`. Name the files you are leaving untouched.

15. Wait for `approve`, `approve with changes: <notes>`, or `abort`. Never write before approval.

16. On approval, write the files. In revise mode, write only the files the preview marked, and leave every other file in the package as it is. Report every path written, and every path removed.

## Rules

- Present before you write. The full draft is the preview, so the user judges real content rather than a summary.
- A revise never rewrites the whole package by default. Change what the request asks for, and preserve every unrelated file.
- If a validation step fails twice in a row, stop and ask. Do not loop.
- Draft the description before the body.
- Copy a reference into the drafted package rather than pointing the drafted package back at this one.
- Keep the drafted package one level deep. A reference does not point at another reference.
- Use `mktemp -d` for any working file, and remove it when the run ends. Never write scratch into the user's project.
- Name the skill for the user's task. Do not carry a framework prefix into a name unless the user asks for one.
