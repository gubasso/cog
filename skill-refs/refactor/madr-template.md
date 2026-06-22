# MADR Template

Format: Markdown Architecture Decision Record (MADR) v3. Spec: <https://adr.github.io/madr/>

The skill scaffolds the first two ADRs at plan-creation time (`0001-rewrite-decision.md`,
`0002-parity-boundary.md`). The implementation agent writes additional ADRs (`0003-*`, …) as it
encounters non-trivial design choices during Phase C.

## Template

```markdown
---
status: proposed | accepted | rejected | deprecated | superseded by adr/NNNN-name.md
date: <YYYY-MM-DD>
decision-makers: [<names or roles>]
consulted: [<names or roles>]
informed: [<names or roles>]
---

# <Short, present-tense title of the decision>

## Context and Problem Statement

<What is the problem? What is the context? What forces are at play? 2–6 sentences. Cite the contract
item or the target-language idiom that forces this decision.>

## Decision Drivers

- <driver 1: e.g. "preserve exit-code contract from 01-CONTRACT.md">
- <driver 2: e.g. "match target-language idiom for error handling">
- <driver 3>

## Considered Options

1. <Option A — one line>
2. <Option B — one line>
3. <Option C — one line>

## Decision Outcome

Chosen option: **<Option X>**. Justification:

<2–4 sentences explaining why this option wins on the drivers above. Cite §6 of the canonical
guideline if rejecting a transliteration shortcut.>

### Consequences

- ✅ <expected positive consequence>
- ✅ <…>
- ⚠️ <known cost, tradeoff, or risk>
- ⚠️ <…>

## Validation

<How will we know this decision is correct? Which parity test pins the behavior? Which property test
exercises it?>

## Pros and Cons of the Options

### <Option A>

- ✅ <pro>
- ❌ <con>

### <Option B>

- ✅ <pro>
- ❌ <con>

### <Option C>

- ✅ <pro>
- ❌ <con>

## References

- Canonical guideline section: `{{GUIDELINE_PATH}}#<anchor>`
- Target-language canon: `{{TARGET_LANG_CANON}}#<anchor>` (if relevant)
- Related ADRs: `adr/NNNN-name.md`
```

## When to write an ADR

Write one when any of the following is true:

1. The decision is hard to reverse (data format, public API shape, error model, concurrency
   primitive).
2. The decision deviates from the contract (any `parity-boundary.not-preserved` item).
3. A reasonable reader would ask "why this and not <obvious alternati".
4. The decision is forced by a target-language idiom that isn't obvious from the contract.

Trivial dependency picks, cosmetic naming, and per-feature tactical decisions do NOT need an ADR.
Use the design files (`design/*.md`) instead.

## Numbering

- `0001` and `0002` are reserved (rewrite decision, parity boundary).
- ADRs created during Phase C start at `0003`.
- Use a 4-digit zero-padded prefix and a kebab-case slug.
- Examples:
  - `0003-error-model.md`
  - `0004-async-runtime-tokio.md`
  - `0005-cli-parser-clap.md`
  - `0006-config-format-toml.md`
  - `9999-postmortem.md` (last ADR, written at end of Phase F).
