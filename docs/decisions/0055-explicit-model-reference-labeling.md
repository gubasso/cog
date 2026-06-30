# ADR-0055: Explicit model/effort/power-grade references in skills

## Context and Problem Statement

[ADR-0053](0053-power-grade-cell-tier-rename.md) fixed the vocabulary: a *cell* is a graded
`(model, effort)` row and a *tier* is a named rung pairing one Claude and one Codex cell. But that
discipline was only enforced on frontmatter (`model-effort-tier`) and in docs, not in skill prose. A
skill could still narrate a model/effort/power-grade reference ambiguously. `review-loop` did exactly
that: it launched Codex at `medium` effort and annotated it "(the Codex HIGH cell)" — naming a *tier*
(`HIGH`, whose Codex cell is `gpt-5.5@medium`) with the noun *cell*. The grade was right but the
phrasing reads as an off-by-one cell error and forces a reader to cross-check the tier ladder. A
reference to a capability axis in a skill must be explicit and well-labeled so it is unambiguous on its
face.

## Considered Options

- Fix `review-loop` and move on, leaving the convention unstated.
- Fix it and document the convention in the skill contract, conformed opportunistically.
- Fix it, document the convention, and add a `cog skill-lint` rule so the labeling is machine-enforced
  across every runtime skill going forward.

## Decision Outcome

Chosen option: **document the convention and machine-enforce it.** A skill's prose names a model,
effort, tier, or power-grade cell by its correct kind: a cell by its `model@effort` or matrix slug, a
tier by "the `<TIER>` tier"; the labeled form names the tier and its cell together (e.g. "the HIGH
tier's Codex cell (`gpt-5.5@medium`)"), and an explicit `--effort <value>` inside a command block
already satisfies it. The `model-effort-prose-label` rule in `cog skill-lint` flags the high-confidence
mislabel — a five-rung tier word (`XHIGH|HIGH|MEDIUM|LOW|CHEAP`) used as the noun "cell" — over runtime
`SKILL.md` bodies (Claude and Codex), skipping frontmatter (already governed by `model-effort-tier`)
and fenced code blocks (where `--effort <val>` is unambiguous). Correct tier prose and explicit cell
prose pass; an inline `<!-- cog-skill-lint: allow-model-ref-label <reason> -->` on the preceding line
records a deliberate exception. The audit at adoption found the whole tree clean except `review-loop`'s
two lines, which were corrected to the labeled form. This complements the cell/tier vocabulary of
[ADR-0053](0053-power-grade-cell-tier-rename.md) and the tier ladder of
[ADR-0041](0041-named-tier-ladder.md)/[ADR-0013](0013-model-effort-policy.md).

## Consequences

- Good: capability references in skills are unambiguous on their face; the mislabel that made a correct
  grade look wrong cannot recur, and a new skill that reintroduces it fails lint.
- Good: the rule is high-confidence (tier-word-as-`cell`) with near-zero false positives, and carries
  an explicit escape hatch for the rare legitimate exception.
- Bad: the rule catches only the tier-as-cell construction, not every conceivable ambiguous phrasing;
  broader ambiguity is left to author judgment and the contract prose.

## Status

Accepted. Enforced by the `model-effort-prose-label` rule in `lib/commands/cmd_skill_lint.sh` and by
the convention in `docs/reference/skill-contract.md` ("Explicit model/effort/power-grade references").
