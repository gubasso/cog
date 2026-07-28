# Re-grade plan-review effort to the session default

> Complexity: S | Rounds: 1 | Generated: 2026-06-22 | Repo: /workspaces/cog

## Problem Statement

`skills/claude/review-plan-lean/SKILL.md` pins `model: opus` + `effort: xhigh` — the only `xhigh` skill in the repo — carried with no inline justification even though the policy requires xhigh overrides to be justified. ADR-0013 originally re-graded this skill's predecessor to the default tier; it has since drifted up to `xhigh` undocumented.

External research (OpenAI + Anthropic reasoning-effort guidance, OpenAI code-verification study, JudgeBench, verification-dynamics work) converged: maximum reasoning effort is not warranted for reviewing an already-reasoned artifact. Generator-verifier asymmetry makes critique cheaper than generation, but correctness judging is non-trivial, so review needs a strong model at a **high** floor — exactly the Claude session default (opus + high). Policy says exploration/review skills ride the default with no override, like sibling skills `review-code-deep` and `review-loop`.

## Strategy

A single cohesive doc/config round: remove the override so the skill rides the default, refine the policy references, record the decision as a new ADR, and preserve the external evidence on the research shelf. The work is mechanically coupled and low-risk (no code logic), so one round is the right size.

## Rounds

The authoritative order and status live in `queue-rounds.yaml`.

1. `apply-effort-regrade.md` — remove the Claude override, refine both TOMLs + the policy doc, add ADR-0027 + its index line, record the research-shelf entry, and run the validation gates.

## Execution Commands

```bash
# executor-lean takes one plan path directly; point it at the round file:
/executor-lean .implementation-plans/plans/re-grade-plan-review-effort/apply-effort-regrade.md
```

## Execution Discipline

**One round per `/executor-lean` session.** Each round is a self-contained unit of work designed for a single `/executor-lean` session. `executor-lean` executes the one plan path it is given; it does not read `queue-rounds.yaml` to auto-select the next round, so each round is launched by pointing `executor-lean` at that round file. Do not implement multiple rounds in one session.

The round file itself owns its queue bookkeeping: its first step sets the round `status` to `doing` and its final step sets it to `done` (and, for the final round, marks the plan `done` in the top-level `queue-plans.yaml`). A crashed or interrupted session thus leaves a visible `doing` marker.

## Decisions & Constraints

- **Remove the override entirely** (do not pin `effort: high`). The session default is already opus + high, and policy says exploration/review skills set no override — matching `review-code-deep` and `review-loop`. (User decision, this session.)
- **New ADR + reference updates** to record the verification-effort principle; the ADR (0027) **extends** ADR-0013 and does not supersede it. The next free ADR number is 0027 because 0024, 0025, and 0026 already exist; confirm at implement time and bump if taken.
- **Record the external evidence** on the research shelf so the justification is durable and reusable.
- Codex twin needs no change — it already rides the default.
- No git operations in this round.
- Executor: executor-lean (EF 1.0). Single-round sizing is unaffected (raw 6 ÷ 1.0 → 6 → S).

## Rejected Alternatives

- **Keep opus+xhigh** — rejected: sole repo outlier, unjustified, contradicted by external evidence on verifier asymmetry and diminishing returns.
- **Pin opus+high explicitly** — rejected: same value as the default but against the policy's "no override for exploration/review" rule; removing is cleaner and matches sibling skills.
- **Reference updates only, no ADR** — rejected: the repo's ADR-heavy decision-traceability discipline warrants recording a new policy principle.

## Risks & Edge Cases

- Low risk overall — docs/config only, no code logic. No tests or lint rules gate on the current frontmatter values (`cog skill-lint` checks key presence, not values).
- If `cog research-shelf validate` rejects a `--source-json` shape, adjust the date/url fields and re-record (handled in the round's Step 7).
- If the Claude session default ever drops below high, review skills follow it — intended exploration-tier behavior, revisited via policy revalidation.

## Completion

When all rounds are done, set the round `done` in this plan's `queue-rounds.yaml` and set this plan `done` in the top-level `.implementation-plans/queue-plans.yaml`. Nothing moves on disk.
