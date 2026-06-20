@AGENTS.md

Non-negotiable: skills orchestrate probabilistic judgment; deterministic mechanics live in cog
subcommands and DRY cog::fn:: helpers. See docs/decisions/0008-skill-script-boundary.md and
docs/reference/skill-contract.md.

Non-negotiable: required runtime references ship in-repo under skill-refs/ and resolve through cog
skill-refs; external docs are optional enhancers only. See
docs/decisions/0017-reference-self-containment.md.

Non-negotiable: skill model/effort selection follows docs/reference/model-effort-policy.md and
docs/decisions/0013-model-effort-policy.md; model: sonnet is forbidden (use model: opus + effort:
low).

Non-negotiable: skill names follow the prefix taxonomy in docs/decisions/0016-skill-prefix-taxonomy.md
and docs/reference/skill-contract.md ("Prefix taxonomy"): plan-* emits plans, review-* reviews code or
plans, review-plan-* is the plan-review sub-namespace, executor-* executes one prompt/plan, and
runner-* orchestrates executor-selected queue items.

Non-negotiable: skills that output a plan must not run in Claude plan mode; they carry a Phase 0
plan-mode gate (markers cog-skill: plan-emitter + cog-plan-mode-gate), enforced by cog skill-lint.
See docs/decisions/0015-plan-skills-not-in-plan-mode.md and docs/reference/skill-contract.md
("Plan-mode gate").
