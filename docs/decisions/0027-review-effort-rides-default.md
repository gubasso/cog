# ADR-0027: Review/verification effort rides the session default

## Context and Problem Statement

ADR-0013 set the model/effort policy: exploration/planning skills ride the session default,
procedural skills use opus+low, and overrides must be justified. The `review-plan-oneshot` skill drifted
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

- Keep review-plan-oneshot at opus+xhigh.
- Pin review-plan-oneshot to opus+high explicitly.
- Treat review/verification as exploration-tier: ride the session default (opus+high), no override.

## Decision Outcome

Chosen option: **treat review/verification as exploration-tier**. Review and verification skills ride
the session default and set no model/effort override, matching review-oneshot and review-loop.
xhigh remains an exception tier requiring documented justification, reserved for reviews that span
many subsystems, are security-critical, are expensive to reverse, or run as evaluations.
review-plan-oneshot is re-graded to the default (override removed).

This extends ADR-0013; it does not supersede it.

## Consequences

- Good: review-plan-oneshot matches its sibling review skills and the policy's exploration tier.
- Good: the verifier-asymmetry rationale is recorded once, with external evidence on the research
  shelf, to guide future review skills.
- Neutral: if the Claude session default ever drops below high, review skills follow it; that is the
  intended exploration-tier behavior, revisited via model-effort policy revalidation.

## Status

Accepted
