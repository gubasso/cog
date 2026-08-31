# ADR-0036: State model and effort explicitly at every delegation

## Context and Problem Statement

ADR-0014's power grade routed model and effort selection through an indirection: a five-rung tier ladder pairing per-provider `(model, effort)` cells, backed by `data/power-grade/matrix` and `data/model-effort/` registries, resolved by `cog power-grade`, and enforced on frontmatter by the `model-effort-tier` lint rule. A skill reader could not see what a delegated agent would actually run without resolving the registry, and the one launch whose effort lived only in tier prose (`review-loop`) carried no literal flag at all.

## Considered Options

- Keep the ladder and require cell prose to name its resolved flag
- Keep the registry for frontmatter but drop tier prose at call sites
- Remove the tier system entirely and state model/effort directly everywhere

## Decision Outcome

Chosen option: `Remove the tier system entirely and state model/effort directly everywhere` — an explicit flag at the call site is the whole policy, so a registry that derives it is pure indirection.

Every coding-agent launch a skill ships states a literal `--effort <value>` on the command; `--model` appears only for a non-default model. An omitted `--model` — and, outside launch commands, an omitted `--effort` — means exactly one thing: the harness default is accepted, deliberately. Both runners (`cog codex-runner run-exec|run-resume`, `cog claude-runner run-exec`) expose `--model` and `--effort` as their invocation contract — the pair this policy requires expressible at every call site — so, like the global operator flags, it is exempt from the per-flag live-caller sweep. Frontmatter `model:`/`effort:` are free explicit values. Review skills run their first cold round at `high` effort on the default model and warm rounds at `medium`. The `model-effort-indirection` and `agent-launch-explicit-effort` lint rules enforce this; the registries, `cog power-grade`, and the `model-effort-tier` rule are deleted.

## Consequences

- Good: every delegation's model and effort are readable at the call site, with lint keeping them explicit.
- Bad: capability guidance is no longer centrally graded; authors consult the dated model references and choose per call.

## Status

Implemented. Supersedes [ADR-0014](./ADR-0014-model-effort-and-power-grade.md). Enacted by [skill contract](../reference/skill-contract.md) and the runner surfaces in [CLI reference](../reference/cli-commands.md).
