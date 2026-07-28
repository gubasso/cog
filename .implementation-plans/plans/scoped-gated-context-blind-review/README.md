# Scoped, Gated, Context-Blind Review Boundary & Skill Governance

> Complexity: L | Rounds: 3 | Generated: 2026-06-20 | Repo: /workspaces/cog

## Problem Statement

`runner-queue` runs the implementation-plan review boundary after **every** committed item (inner round _and_ main plan). Three problems motivate this work:

1. **Cost / scope mismatch.** The boundary always runs a _global_ Opus pass over the whole `.implementation-plans/` tree, even when only one plan's inner rounds changed. A local inter-round drift should not trigger a whole-project re-analysis.
2. **The full review is thinner than intended.** Today the skill reconciles only the _just-landed_ plan's own mutable items and appends gaps; it does not systematically ask whether _other_ queued plans are now redundant / conflicting / stale versus the landed code.
3. **It is project-local and not self-contained.** It lives at `.claude/skills/...`, is loaded via a cwd hack, and bakes its context (always-global) into the skill instead of letting the caller drive it.

The fix introduces a **context-blind, self-contained** review skill that behaves like a CLI program: phases behind flags, defaults to cheap deterministic checks, gates the expensive LLM pass behind `--full-review`, accepts a `--scope`, and returns a machine-first report. **Callers own context** and drive the flags — a new repo golden rule. Deterministic mechanics stay in `cog` scripts; only the semantic analysis is LLM. The full review **auto-applies guarded** cross-plan reconciliation. Scope bounds the analysis: between rounds → only that plan's rounds queue; between plans → global. Finally, the repo's skill-authoring tooling is brought into line: `cog-skill-creator` must read and follow **every** repo rule, and a new `cog-skill-reviewer` reviews any repo skill against those rules and can fully refactor it.

## Strategy

Three heavy, dependency-ordered rounds, each a substantial `/executor-prex` chunk:

1. **`cog` deterministic foundation** — rename the command family, add scoping, add the gate command, migrate every reference, and prove it all with tests. Pure scripts; no LLM behavior.
2. **Review skill + runner integration + governance** — relocate and rewrite the skill as a context-blind, scoped, gated, auto-applying tool; rewire `runner-queue` to drive it per context; land the superseding ADR and the new golden rule.
3. **Skill-governance meta-tooling** — make `cog-skill-creator` follow every repo rule and create `cog-skill-reviewer`, both grounded on the now-finalized rule set.

Round 1 is the foundation everything calls; Round 2 builds the skill and integration on it and establishes the rules; Round 3 builds the tooling that enforces those rules. The dependency chain is strictly linear.

## Rounds

The authoritative order and status live in `queue-rounds.yaml`; this list mirrors it.

1. `cog-deterministic-foundation.md` — rename `review-implementation-plans-*` → `review-plan-implementation-plans-*`, add `--scope`/`--queue` + scoped helpers, add the deterministic `-gate` command, sweep all references, rename/extend/add bats.
2. `review-skill-and-runner-integration.md` — relocate + rewrite the context-blind scoped/gated auto-applying skill, rewire `runner-queue`, add the superseding ADR + the caller-owns-context golden rule.
3. `skill-governance-meta-tooling.md` — make `cog-skill-creator` follow every repo rule (self-contained refs), and create the new `cog-skill-reviewer` skill.

## Execution Commands

```bash
# Execute the next todo round (executor reads queue-rounds.yaml, runs the first todo round, then stops):
/executor-prex -ar @.implementation-plans/plans/scoped-gated-context-blind-review/

# Or target a specific round file directly:
/executor-prex -ar .implementation-plans/plans/scoped-gated-context-blind-review/cog-deterministic-foundation.md
```

## Execution Discipline

**Rounds must be executed one at a time.** Each round is a self-contained unit of work designed for a single `/executor-prex` session. Do not implement multiple rounds in one session.

When `/executor-prex` is pointed at this directory or this `README.md`, it MUST:

1. Read this plan's `queue-rounds.yaml`.
2. Find the first round with status `todo`.
3. Set that round's `status` to `doing`, execute ONLY that round, then set it to `done` and stop.
4. End the session — a fresh `/executor-prex` session is launched for any subsequent round.

## Decisions & Constraints

- **Executor: executor-prex (EF 1.5).** Rounds are deliberately heavy — each is sized to use the full potential of a `/executor-prex` run (Codex plan → Claude review → Codex implement → Claude review-loop). Small-scope rounds are intentionally avoided per the requester's directive.
- **Skill name `review-plan-implementation-plans`** (under the `review-plan-*` taxonomy sub-namespace). Keeps `skill-lint` green with **no lint change**: `is_plan_reviewer_intent` already fires (plan-emitter marker + the "review implementation plans" phrase), expecting a `review-plan` prefix that the new name's class matches. Keep the `plan-emitter` marker + plan-mode gate; remove the `superseded-by review-plan-implementation` marker and all references to that look-alike name.
- **`cog` command family renamed to match the skill:** `review-plan-implementation-plans-scan` / `-verify` / new `-gate`. Helper file/functions rename in step.
- **Self-contained + caller-owns-context:** the skill is blind; the caller passes flags/scope. This becomes a documented repo golden rule.
- **Scope:** the full review runs only against the scope the caller passes (`rounds` vs `global`).
- **Cross-plan edits:** auto-apply (guarded) via `cog queue-*` and mutable prose edits only; never touch `done`/`doing` status, prompt, deps, notes, prose, or order.
- **Golden rule reaffirmed:** determinism in scripts, probabilistic judgment in the LLM.
- **The `global` deterministic path stays byte-identical** so the runner main loop and existing tests are unaffected (regression-guarded).
- **`cog-skill-creator` / `cog-skill-reviewer` stay project-local** (`.claude/skills/`) — they are cog's own development tooling, per the requester's stated paths.

## Rejected Alternatives

- **Decouple plan-mode-gate enforcement from `plan-emitter` to keep the name `review-implementation-plans`.** Rejected: renaming to `review-plan-implementation-plans` satisfies the taxonomy with **zero** skill-lint changes, which is strictly simpler.
- **Runner runs a separate cheap `cog` gate but the skill stays context-aware.** Rejected: the requester chose a self-contained, blind skill driven by caller flags; the gate is a deterministic command both the runner and the skill can use, but context lives with the caller.
- **Flag-and-report-only cross-plan analysis.** Rejected: requester chose auto-apply (guarded).

## Risks & Edge Cases

- **Auto-apply widens the mutation surface** to _other_ mutable plans. Mitigation: immutability of `done`/`doing` and cog-only mutation, enforced by `verify`.
- **The command-family rename is a broad mechanical sweep** (modules, handlers, helpers, tests, completions, man, cli-commands, skill + runner-queue tokens). Mitigation: Round 1 contains the whole sweep and leaves the repo coherent; precedent exists (the recent `executor-prex → executor-prex` migration).
- **Transient breakage between rounds.** Mitigation: each round leaves a coherent, lint-clean, test-green state; the rename and all its consumers land together in Round 1.
- **Heavy rounds may approach the one-Codex-600s-session ceiling.** Accepted per the requester's explicit "heavy rounds only" directive; the in-round review-loop (EF 1.5) absorbs the size.

## Completion

When all rounds are done, set each round `done` in this plan's `queue-rounds.yaml` and set this plan `done` in the top-level `.implementation-plans/queue-plans.yaml`. Nothing moves on disk.
