# ADR-0020: Remove Superseded Skills and Migration Shims; Complete Pending Renames

> Note (ADR-0064): the `review-plan-implementation` rename completed here was itself superseded — the boundary is now `review-queue-rounds`. This body is left as the historical record.

## Context and Problem Statement

After ADR-0018 removed the `tsk`/`prex` surfaces, the repo still carried two classes of legacy: superseded-marked skills whose pending renames from ADR-0015/0016 were never enacted, and backward-compat migration shims in the CLI that no longer had a live consumer.

The superseded skills were `plan-reviewer` (a `superseded-by review-plan-claude` shim whose replacement already shipped), and two skills carrying forward-declared but unbuilt replacements: `refactor-migration-plan` (`superseded-by plan-refactor-migration`) and the project-local `review-implementation-plans` (`superseded-by review-plan-implementation`). The `superseded-by` marker was also the only reason the latter two passed `cog skill-lint`: their names violate the ADR-0016 prefix taxonomy, and the marker was the escape hatch.

The migration shims were: the `cog preflight claude-env --allow-legacy-session` advisory downgrade (an env-rollout grace path), the `cog plan-init` `legacy_plan_dir` detection of the obsolete `.plan` directory, the `superseded-by` lint facility itself (a skill-rename grace path), the `quick`/`deep` legacy Codex effort aliases mapped to native `low`/`high`, and the runner commit parser's dual output shape (a single bare `COMMIT_OK <sha>` line emitted a legacy `{commit_sha, line}` JSON object instead of the multi-repo `{ok, commits[]}` shape used by every other input).

## Considered Options

- Keep the superseded skills and shims as compatibility layers.
- Remove only the provably-dead surfaces; keep the functional migration shims.
- Remove the dead skill, complete the two pending renames, and remove the functional shims.

## Decision Outcome

Chosen option: **remove all legacy and converge on the current contract.**

- `plan-reviewer` is deleted; `review-plan-claude`/`review-plan-codex` are the plan-review skills.
- `refactor-migration-plan` is renamed to `plan-refactor-migration` (Claude + Codex), enacting the ADR-0016 taxonomy; its backing `cog refactor-*` commands keep their names.
- `review-implementation-plans` is renamed to `review-plan-implementation` end to end: the project-local skill, the `cog review-plan-implementation-scan`/`-verify` commands, the `cog::fn::review_plan_implementation_*` helpers, and every man/completion/doc/test reference.
- The migration shims are removed: `--allow-legacy-session` (preflight `claude-env` is now always strict/fail-closed), the `legacy_plan_dir` field, the `superseded-by` lint facility (the `cog::fn::skill::superseded_by` helper and the taxonomy escape hatch), and the `quick`/`deep` effort aliases (skills use native `minimal|low|medium|high`; escalation is `--effort high`).
- The runner commit parser always emits the `{ok, commits[]}` JSON shape; the single-repo legacy `{commit_sha, line}` branch is gone. Human output is unchanged (a bare line still prints `COMMIT_SHA=<sha>`), and a bare single-repo line is still accepted as input.

All three `superseded-by` markers are gone, so no skill depends on the escape hatch. The intentional hard-fail guardrails that block removed flags (`cog codex-runner` rejecting `--profile`, `executor-prex` rejecting `-t`) are kept — they prevent silent breakage rather than carry legacy.

## Consequences

- Good: one canonical name per skill; a taxonomy-clean skill set with no superseded markers; leaner CLI with no dead migration branches; native-only Codex effort vocabulary.
- Bad: behavior-affecting changes — `cog preflight claude-env` no longer has an advisory mode (a session without `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1` fails closed), `cog plan-init` no longer reports `legacy_plan_dir`, `--effort deep`/`quick` are rejected, and a future mis-prefixed skill must be renamed (it can no longer pass lint via a `superseded-by` marker).

## Status

Implemented. Enacts the pending renames noted in ADR-0015 (plan-skills-not-in-plan-mode) and ADR-0016 (skill-prefix-taxonomy), and completes the legacy-removal direction of ADR-0018; those accepted ADRs remain as historical record. ADR-0014 (review-implementation-plans boundary) describes the pre-rename skill and is unchanged.
