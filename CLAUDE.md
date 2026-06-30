@AGENTS.md

Non-negotiable: skills orchestrate probabilistic judgment; deterministic mechanics live in cog
subcommands and DRY cog::fn:: helpers. See docs/decisions/0008-skill-script-boundary.md and
docs/reference/skill-contract.md.

Non-negotiable: skill-refs/ is the single SoT for every skill-external resource - read-only
references under skill-refs/<area>/ and deploy-payload templates under skill-refs/templates/<domain>/
- shipped in-repo and resolved through cog skill-refs / cog::fn::skill_refs_root; external docs are
optional enhancers only. See docs/decisions/0017-reference-self-containment.md and
docs/decisions/0023-skill-refs-unified-resource-sot.md.

Non-negotiable: top-level data/ is the SoT for structured reference data consumed by the cog CLI
itself. CLI data is YAML split one file per top-level table, except append-only streams such as
data/research-shelf/index.jsonl, and resolves through cog::fn::data_root so installs use
$XDG_DATA_HOME/cog/data.

Non-negotiable: runtime skills never depend on docs/reference/codex-conventions.md or
DOCS_NOTES_REPO. Codex behavior comes from cog codex-runner, and load-bearing shared references are
imported to skill-refs and resolved with cog skill-refs path. Shared judgment workflows delegate to a
canonical runtime skill instead of reimplementing the workflow inline. See
docs/decisions/0024-skill-reference-self-containment-golden-rules.md and
docs/decisions/0025-sot-executor-delegation.md.

Non-negotiable: skill model/effort selection follows docs/reference/model-effort-policy.md and
docs/decisions/0013-model-effort-policy.md; model: sonnet is forbidden (use model: opus + effort:
low). A governed Claude skill's model:/effort: must resolve to its expected tier, enforced by cog
skill-lint (model-effort-tier); the authoritative registry is the per-tier skills lists in
data/model-effort/claude/tiers.yaml (the single escape hatch for exceptions), and authors verify
with cog power-grade skill-tier / cog power-grade tier. See
docs/decisions/0047-enforce-prefix-tier-policy.md and docs/reference/skill-contract.md
("Model/effort tier enforcement").

Non-negotiable: skill names follow the prefix taxonomy in docs/decisions/0016-skill-prefix-taxonomy.md
and docs/reference/skill-contract.md ("Prefix taxonomy"): plan-* emits plans, review-* reviews code or
plans, review-plan-* is the plan-review sub-namespace, executor-* executes one prompt/plan, and
runner-* orchestrates executor-selected queue items.

Non-negotiable: native twin skills share one base name across skills/claude/ and skills/codex/;
platform-token suffixes are reserved for delegation launchers that run the other platform under the
hood. See docs/decisions/0021-twin-skill-naming-and-delegation-hints.md and
docs/reference/skill-contract.md ("Twin and delegation skill naming").

Non-negotiable: machine-facing skill identifiers are stage-agnostic: run-dir artifact filenames,
skill reference filenames, handoff/JSON fields, CLI flags, and executor ordinal values are named for
role or content, not stage number. Enforced by cog skill-lint (stage-agnostic-identifiers). See
docs/decisions/0040-stage-agnostic-identifiers.md and docs/reference/skill-contract.md
("Stage-agnostic identifiers").

Non-negotiable: the plan-mode gate lives on the executor-*/runner-* orchestrator layer, not on plan or
review workers. Every Claude executor-*/runner- skill carries a Phase 0 plan-mode gate
(cog-plan-mode-gate marker); every other Claude skill must not. The gate wording is a single source of
truth rendered by cog gate render --id plan-mode and stamped, never hand-written; cog skill-lint fails an
executor/runner missing the gate or whose stanza drifts, and fails any other skill that carries it. See
docs/decisions/0015-plan-skills-not-in-plan-mode.md, docs/decisions/0037-plan-mode-gate-canonical-render.md,
docs/decisions/0045-unified-gate-command-and-context-brief-verbs.md,
and docs/reference/skill-contract.md ("Plan-mode gate").

Non-negotiable: skill prose is lean, objective, and positively framed - describe what the skill IS
and MUST DO. Avoid preemptive negative guardrails that never had an empirical reason; negative or
exclusion statements are allowed only when explicitly requested or correcting a recurrent drift.
Runtime skill files carry no source-repo meta (no skills/.../SKILL.md cross-references); such meta
belongs in docs/. The source-path part is enforced by cog skill-lint (skill-source-path-reference).
See docs/decisions/0019-lean-positive-skill-prose.md and docs/reference/skill-contract.md
("Lean positive prose").

Non-negotiable: a consumer skill depends only on its structural input contract (the
.implementation-plans/ directory structure, the shared structured-findings contract) and is blind to
which skill produced that input; it never names the producer in prose, and all input validation is
delegated to cog. Enforced by cog skill-lint (producer-blindness) via a curated consumer->producer
map. See docs/decisions/0026-consumer-skill-producer-blindness.md and
docs/reference/skill-contract.md ("Producer-blind consumers").

Non-negotiable: a brief-building delegator passes the best-constructed input to fresh-context workers:
a well-oriented objective crafted from the whole session, the raw request attached as-is, and the full
substantive context and artifacts (decisions, research, findings, generated plans) that bear on the
task. Summarize narrative for clarity, but carry the full substance where necessary; the coordinator's
own verdict or proposed solution is the deliberate omission for bias isolation. Enforced by cog
skill-lint (input-fidelity) via a curated delegator set and marker. The general structural shape is the
context-brief convention (skill-refs/orchestration/context-brief-contract.md), built and validated
through the canonical context-builder skill and cog context-brief (build --request attaches the raw
request); context-building runs inline in the caller's context, never as a blind subagent. See
docs/decisions/0043-best-constructed-input-standard.md (supersedes
docs/decisions/0035-input-fidelity-enrichment-only-briefs.md),
docs/decisions/0042-context-builder-shared-capability.md, and docs/reference/skill-contract.md
("Input fidelity (best-constructed input)", "Context brief (general input convention)").
