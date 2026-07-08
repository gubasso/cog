## Stage 1: Build Plan

Draft the implementation plan with Codex by inline-chaining `plan-oneshot-codex` in the current
context: read the skill at `$HOME/.claude/skills/plan-oneshot-codex/SKILL.md` and follow it. The
delegation input is the validated context brief `$RUN_DIR/context-brief.md` built above — pass it as the
best-constructed input per `$(cog skill-refs path orchestration/context-brief-contract.md)` (attach the
request as-is plus relevant repo constraints, carrying the full substance) — together with the output
path `$RUN_DIR/draft-plan.md`.

`plan-oneshot-codex` owns the durable Codex plan job (`cog codex-runner run-exec --effort medium` →
`finalize`), drafting the plan at native effort `medium`, and writes the saved plan to
`$RUN_DIR/draft-plan.md`. Do not pre-create or pre-format the artifact. Verify it before continuing to
the plan-review stage:

```bash
[ -s "$RUN_DIR/draft-plan.md" ] || { echo "ERROR: draft-plan.md is empty" >&2; cog lock release "$LOCK_FILE"; exit 1; }
```

The drafted plan is a candidate, not yet authoritative: the plan-review stage vets and reconciles it
into `vetted-plan.md`, which the implementation stage consumes.
