# Re-grade plan-review effort to the session default

> Plan: re-grade-plan-review-effort | Round: 1 of 1 | Complexity: S | Generated: 2026-06-22 |
> Repo: /workspaces/cog

## Context

`skills/claude/review-plan-lean/SKILL.md` pins `model: opus` + `effort: xhigh`. It is the **only**
`xhigh` skill in the repo, and it carries no inline justification even though the policy
(`docs/reference/model-effort-claude.toml` exploration `escalation` clause) requires xhigh overrides
to be justified. ADR-0013 originally re-graded the predecessor of this skill to the default tier; it
has since drifted up to `xhigh` undocumented.

External research (OpenAI + Anthropic reasoning-effort guidance, OpenAI code-verification study,
JudgeBench, verification-dynamics work) converged: maximum reasoning effort is not warranted for
**reviewing** an already-reasoned artifact. Generator-verifier asymmetry makes critique cheaper than
generation, but correctness judging is non-trivial (LLM judges go near-random on hard cases), so
review needs a strong model at a **high** floor — not minimal, not max. xhigh/max are exception tiers
with diminishing returns. The Claude session default is already `opus + high`, and policy says
exploration/review skills ride the default with no override (like sibling skills `review-code-deep`
and `review-loop`). Therefore the cleanest fix is to **remove the override entirely**.

This round applies that re-grade, records the policy refinement (a new ADR + reference updates), and
preserves the external evidence on the research shelf. The codex twin
(`skills/codex/review-plan-lean/SKILL.md`) already sets no override and needs no change.

## Previous Rounds

This is the first round — no prior rounds.

## Scope of This Round

IN scope:

- Remove `model:` + `effort:` from the Claude `review-plan-lean` frontmatter.
- Refine the model/effort policy references (both TOMLs + the human-readable policy doc).
- Add a new ADR (0026) and its `docs/README.md` index line.
- Record the external evidence on the research shelf.
- Run the validation gates.

OUT of scope:

- Re-grading any other skill (review-plan-lean is the sole `xhigh` user).
- Changing the codex twin (already rides the default).
- Building a `cog model-policy` command or changing `cog codex-runner` wiring.
- Any git operation (staging, committing, branching).

## Current State

### Key Files

- `skills/claude/review-plan-lean/SKILL.md` — the skill to re-grade. Current frontmatter:

  ```yaml
  ---
  name: review-plan-lean
  description: >
    Review one implementation plan before concrete implementation, using the
    persisted research shelf for reusable context and saving the annotated
    review through cog plan-review.
  model: opus
  effort: xhigh
  argument-hint: "<plan-path-abs> <request-path-abs> <output-path-abs>"
  disable-model-invocation: true
  allowed-tools: Bash Read Write Grep Glob WebSearch WebFetch
  ---
  ```

  Remove **only** the `model: opus` and `effort: xhigh` lines; keep every other field.

- `docs/reference/model-effort-claude.toml` — Claude policy data. The `[tiers.exploration]` block
  currently has:

  ```toml
  examples = ["ask", "plan-writer", "plan-writer-multi", "executor-prex", "review-loop", "review-code-deep", "cog-skill-creator"]
  ```

  and:

  ```toml
  escalation = """A skill author may override per case, such as effort=xhigh for an unusually hard
  task, but the override must be justified in the skill or invocation context."""
  ```

- `docs/reference/model-effort-codex.toml` — Codex policy data. The `[tiers.exploration]` block
  currently has:

  ```toml
  examples = ["ask", "plan-writer", "plan-writer-multi", "executor-prex", "review-loop", "review-code-deep"]
  ```

- `docs/reference/model-effort-policy.md` — human-readable policy. Has sections `## Defaults`,
  `## Tiers`, `## How To Classify Work`, `## Evidence And Revalidation`, `## Follow-Ups`.

- `docs/decisions/0013-model-effort-policy.md` — the ADR this change extends (not supersedes).

- `docs/README.md` — index only; ADR list currently ends at line 32:

  ```text
  - [ADR-0025: SoT executor delegation](decisions/0025-sot-executor-delegation.md)
  ```

- `docs/decisions/template.md` — the ADR template the new ADR must follow.

### Existing Patterns

- ADR numbering is sequential zero-padded; the next free number is **0026** (0024 and 0025 already
  exist). Accepted ADRs are never deleted; changed decisions get a new ADR. This ADR **extends**
  0013, it does not supersede it.
- Markdown fenced code blocks must declare a language (`text` when none applies) — markdownlint
  MD040.
- TOML escalation/rationale fields use `"""triple-quoted"""` multi-line strings.
- Skill prose / policy prose is lean, objective, positively framed (ADR-0019).
- The research-shelf `record` command signature:

  ```text
  cog research-shelf record [--root <dir>] [--id <id>] --topic-tags <csv>
    --source-json <json> [--source-json <json> ...] --summary <text>
    --revalidate-after <date> --consuming-skills <csv> [--recorded-date <date>] [--json]
  ```

## Implementation Steps

### First Step: Mark this round as started

In this plan's `queue-rounds.yaml`, set this round's (`item: apply-effort-regrade`) `status` to
`doing`.

### Step 1: Remove the override from the Claude skill

Edit `skills/claude/review-plan-lean/SKILL.md` and delete these two lines from the frontmatter:

```yaml
model: opus
effort: xhigh
```

Leave `name`, `description`, `argument-hint`, `disable-model-invocation`, and `allowed-tools`
untouched. The skill now rides the session default (opus + high).

### Step 2: Add review-plan-lean to the exploration examples (both TOMLs)

In `docs/reference/model-effort-claude.toml`, append `"review-plan-lean"` to the
`[tiers.exploration].examples` array:

```toml
examples = ["ask", "plan-writer", "plan-writer-multi", "executor-prex", "review-loop", "review-code-deep", "cog-skill-creator", "review-plan-lean"]
```

In `docs/reference/model-effort-codex.toml`, append `"review-plan-lean"` to the
`[tiers.exploration].examples` array:

```toml
examples = ["ask", "plan-writer", "plan-writer-multi", "executor-prex", "review-loop", "review-code-deep", "review-plan-lean"]
```

### Step 3: Refine the xhigh escalation clause (Claude TOML)

In `docs/reference/model-effort-claude.toml`, replace the `[tiers.exploration].escalation` value
with one that captures the verifier-asymmetry principle (keep it lean and positive):

```toml
escalation = """A skill author may override per case when a task is genuinely harder than open
exploration, and the override must be justified in the skill or invocation context. Reviewing or
verifying an already-reasoned artifact (plan review, code review) rides the session default:
generator-verifier asymmetry makes critique cheaper than generation, tempered by the difficulty of
correctness judging, so opus+high is the right floor. Reserve effort=xhigh for reviews that span many
subsystems, are security-critical, are expensive to reverse, or run as evaluations."""
```

### Step 4: Add a "Review And Verification Work" subsection to the policy doc

In `docs/reference/model-effort-policy.md`, add a new section immediately before
`## Evidence And Revalidation`:

```markdown
## Review And Verification Work

Reviewing or verifying an already-reasoned artifact (plan review, code review) is exploration-tier
work: it rides the session default (Claude opus + high; Codex gpt-5.5 + medium) and sets no
frontmatter override. Generator-verifier asymmetry makes critique cheaper than generation, but
correctness judging is non-trivial, so the high default is the right floor rather than a reduced
tier. Reserve the xhigh/max exception tiers for reviews that span many subsystems, are
security-critical, are expensive to reverse, or run as evaluations. See ADR-0026 and the
research-shelf entry tagged `verifier-asymmetry`.
```

### Step 5: Write ADR-0026

Create `docs/decisions/0026-review-effort-rides-default.md` following `docs/decisions/template.md`
(mirror the section shape of `docs/decisions/0013-model-effort-policy.md`):

```markdown
# ADR-0026: Review/verification effort rides the session default

## Context and Problem Statement

ADR-0013 set the model/effort policy: exploration/planning skills ride the session default,
procedural skills use opus+low, and overrides must be justified. The `review-plan-lean` skill drifted
to `model: opus` + `effort: xhigh` — the only `xhigh` skill in the repo — with no inline
justification, which the escalation clause requires. This raised the question of what effort a
plan/code review (verifying an already-reasoned artifact) actually warrants.

External research (OpenAI and Anthropic reasoning-effort guidance, OpenAI's code-verification study,
JudgeBench, verification-dynamics work) converged: maximum reasoning effort is not warranted for
reviewing an existing artifact. Generator-verifier asymmetry makes critique cheaper than generation;
lower-budget reviewers already catch most high-severity issues. But correctness judging is
non-trivial — LLM judges go near-random on hard cases — so review needs a strong model at a high (not
minimal) floor. The xhigh/max tiers are framed by both vendors as exception tiers with diminishing
returns.

## Considered Options

- Keep review-plan-lean at opus+xhigh.
- Pin review-plan-lean to opus+high explicitly.
- Treat review/verification as exploration-tier: ride the session default (opus+high), no override.

## Decision Outcome

Chosen option: **treat review/verification as exploration-tier**. Review and verification skills ride
the session default and set no model/effort override, matching review-code-deep and review-loop.
xhigh remains an exception tier requiring documented justification, reserved for reviews that span
many subsystems, are security-critical, are expensive to reverse, or run as evaluations.
review-plan-lean is re-graded to the default (override removed).

This extends ADR-0013; it does not supersede it.

## Consequences

- Good: review-plan-lean matches its sibling review skills and the policy's exploration tier.
- Good: the verifier-asymmetry rationale is recorded once, with external evidence on the research
  shelf, to guide future review skills.
- Neutral: if the Claude session default ever drops below high, review skills follow it; that is the
  intended exploration-tier behavior, revisited via model-effort policy revalidation.

## Status

Accepted
```

### Step 6: Index the ADR in docs/README.md

In `docs/README.md`, add this line immediately after the ADR-0025 entry (currently line 32):

```text
- [ADR-0026: Review/verification effort rides the session default](decisions/0026-review-effort-rides-default.md)
```

### Step 7: Record the external evidence on the research shelf

Run from the repo root:

```bash
cog research-shelf record \
  --topic-tags "model-effort,verifier-asymmetry,plan-review,reasoning-effort,official-docs" \
  --source-json '{"access-date":"2026-06-22","publisher":"OpenAI","title":"Scaling code verification","url":"https://alignment.openai.com/scaling-code-verification/"}' \
  --source-json '{"access-date":"2026-06-22","publisher":"OpenAI","title":"Reasoning guide","url":"https://developers.openai.com/api/docs/guides/reasoning"}' \
  --source-json '{"access-date":"2026-06-22","publisher":"Anthropic","title":"Extended thinking","url":"https://platform.claude.com/docs/en/build-with-claude/extended-thinking"}' \
  --source-json '{"access-date":"2026-06-22","publisher":"OpenReview","title":"JudgeBench","url":"https://openreview.net/forum?id=G0dksFayVq"}' \
  --source-json '{"access-date":"2026-06-22","publisher":"arXiv","title":"Verification dynamics in LLMs (2509.17995)","url":"https://arxiv.org/html/2509.17995v1"}' \
  --summary "For LLM plan/code review (verifying an existing reasoned artifact), maximum reasoning effort is not warranted. Verifier asymmetry makes critique cheaper than generation, but correctness judging is non-trivial (JudgeBench: LLM judges near-random on hard cases), so review needs a strong model at a high (not minimal) effort floor. Anthropic/OpenAI frame xhigh/max as exception tiers with diminishing returns. Recommendation: review skills ride the session default (Claude opus+high); reserve xhigh for multi-subsystem, security-critical, expensive-to-reverse, or eval reviews." \
  --revalidate-after "2026-09-22" \
  --recorded-date "2026-06-22" \
  --consuming-skills "review-plan-lean,executor-lean,executor-lean-codex,executor-prex" \
  --json
```

If `cog research-shelf validate` later rejects the entry, adjust the offending `--source-json` field
shape (date/url) and re-record.

### Step 8: Validate

Run the gates and confirm they pass:

```bash
cog skill-lint skills/claude/review-plan-lean/SKILL.md
cog research-shelf validate --json
rg -n "xhigh" skills/ || echo "no xhigh in skills (expected)"
rg -n "review-plan-lean" docs/reference/model-effort-claude.toml docs/reference/model-effort-codex.toml
just lint
```

Fix any failures before completing. Do not run any git commands.

### Final Step: Update the queue

1. In this plan's `queue-rounds.yaml`, set this round's (`item: apply-effort-regrade`) `status` to
   `done`.
2. All rounds are now done, so in the top-level `.implementation-plans/queue-plans.yaml` set this
   plan's (`item: re-grade-plan-review-effort`) `status` to `done`. Leave the plan directory in
   place.

## Acceptance Criteria

- [ ] `skills/claude/review-plan-lean/SKILL.md` no longer contains `model:` or `effort:` lines; all
      other frontmatter fields are intact.
- [ ] `rg -n "xhigh" skills/` returns no matches.
- [ ] `"review-plan-lean"` appears in `[tiers.exploration].examples` in both
      `model-effort-claude.toml` and `model-effort-codex.toml`.
- [ ] The Claude TOML escalation clause states that review/verification rides the default and lists
      the xhigh exception cases.
- [ ] `docs/reference/model-effort-policy.md` has a `## Review And Verification Work` section.
- [ ] `docs/decisions/0026-review-effort-rides-default.md` exists, follows the template, and is
      marked `Accepted`.
- [ ] `docs/README.md` lists the ADR-0026 entry after ADR-0025.
- [ ] A research-shelf entry tagged `verifier-asymmetry` (consuming `review-plan-lean`) exists and
      `cog research-shelf validate` passes.
- [ ] `cog skill-lint skills/claude/review-plan-lean/SKILL.md` passes.
- [ ] `just lint` passes on the touched files.
- [ ] This plan's `queue-rounds.yaml` shows round `apply-effort-regrade` as `done`.
- [ ] The top-level `.implementation-plans/queue-plans.yaml` shows this plan as `done`.

## Next Round

This is the final round.
