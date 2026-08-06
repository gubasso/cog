# 002 — Workflow engine go or no-go

<!-- markdownlint-configure-file { "MD043": { "headings": ["# 002 — Workflow engine go or no-go","## Goal","## Appetite","## Core","## In scope","## Out of scope","## Governed by","## Acceptance","## Rabbit holes","## Done when","## Revisions"] } } -->

## Goal

The project records one explicit accepted or rejected workflow-engine decision after Q-001 through Q-004 close.

## Appetite

2 implementation sessions. Chosen before the design below.

## Core

An ADR accepts or rejects the workflow engine, fixes its grammar and invocation boundary, and leaves no engine code written before that decision. The remainder funds evidence review and contract cleanup.

## In scope

This is the ordered negotiable remainder, cut last-first from the bottom of the list.

- Decide `--tier`, including its data source and whether inert `context: inherit` receipt cells are rewritten.
- Choose the legal `plan-split` shape, the declaration home for `sync:`, and the required-input launch grammar.
- Carry the proposed grammar this decision accepts, rejects, or revises. A workflow is a DAG of steps; a step is exactly one of three call forms, discriminated by its kind key. `step:` is a leaf that runs a skill and takes `id`, `as`, `cell`, `needs`, `inputs`. `workflow:` is a composite by reference and takes `id`, `as`, `needs`, `inputs`, `cells`. `loop:` is a composite inline and takes `as`, `needs`, `inputs`, `until`, `max_rounds`, `steps`. Exactly one kind key per entry, and `needs:` is the only edge key: it points at siblings, never crosses a scope boundary, and is never a call.
- Carry the two disjoint name spaces. `id:` names the definition, is unique within its directory, and resolves to a file. `as:` names this instantiation, is unique within this DAG, and is what `needs:` targets. `as:` defaults to `id:`, so only fan-out pays for the distinction.
- Carry the per-step key contract: `cell:` is required on every leaf; `cells:` appears on `workflow:` nodes only; `context:` is `fresh` by default or `inherit`; `outputs:` is declared on the definition rather than the call site, so `${{ steps.<as>.outputs.<handle> }}` is checkable before anything runs. A leaf declares each handle as either a bare filename, meaning a file in the step's run directory, or a typed object, meaning a scalar the step writes to `scalars.json`.
- Carry the four shape rules that keep the DAG readable. Fan-out is the DAG itself: one engine per step, siblings with no edge between them, joined by a step that `needs:` them all, with no `matrix:` and no fold operator, and `combine:` reserved for power-grade. Repetition is `loop:`, with `until:` and `max_rounds:` both required, `until:` evaluated after each full pass in the loop's own scope, and the containing step's outputs being the last round's. A loop is a runtime scope, not a resolve-time expansion: composites flatten statically into dotted sibling handles, a loop resolves to one node of `kind: loop` carrying an unexpanded but fully validated template, and rounds materialize one at a time. There are no conditionals: no `if:` key, no predicate on a step, and no skip state, so every node that exists in the run graph runs and the join question never arises.
- If accepted, carry the literal-cell contract: leaf `cell:` values and caller `cells:` overrides are file literals; overrides reach direct children only; precedence is distance from launch, outermost writer wins.
- If accepted, carry the provider effort ladders: Claude `none`, `low`, `medium`, `high`, `xhigh`, `max`; Codex `minimal`, `low`, `medium`, `high`, `xhigh`.
- If accepted, seed exactly eleven cells: `claude-haiku-4.5-none`; `claude-opus-4.8-{low,medium,high,xhigh,max}`; `codex-gpt-5.5-{minimal,low,medium,high,xhigh}`.
- If accepted, preserve five validator invariants: derived ids, unique ids, exactly four fields, provider-valid efforts, and an existing provider runner.
- Carry the whole expression dialect, one dialect for both `until:` and every `inputs:` value: paths `inputs.<name>` and `steps.<as>.outputs.<handle>`; literals that are integers, single-quoted strings, `true`, or `false`; comparison `==` and `!=`; boolean `&&`, `||`, and `!`; and `( )` for grouping. Nothing else — no arithmetic, no function calls, no string manipulation, no indexing — so the grammar stays fully testable and cannot drift into a scripting language. Evaluation is structural and never invokes a shell, and the spelling is `${{ }}` rather than `${ }` because these values reach command lines in a Bash CLI. This narrowed grammar is cut last because it prevents resurrecting removed join modes.
- Carry the output-visibility rules. `outputs:` is optional and its absence is meaningful: a step declaring nothing produces the implicit handle `stdout`, the agent's final message captured verbatim, so `stdout` is reserved and a definition may not redeclare it. The implicit handle belongs to a leaf and only a leaf: a `workflow:` or `loop:` node runs no agent, so `stdout` is not a handle on a composite at all and referencing it is a validation error rather than an empty string. A composite exports what its own `outputs:` block re-exports and nothing else, which is what lets it be rewritten internally as long as its declared inputs and outputs still mean what they meant.

## Out of scope

- Engine code, data files, commands, or runtime skills.
- Treating shaped successor slices as approval.
- Provider credential management or autonomous scheduling.

## Governed by

- `docs/plan/open-questions.md` — the four blocking choices.
- `docs/decisions/0014-model-effort-and-power-grade.md` — the current tier concept that must remain intact unless a later decision changes only workflow use.
- `skill-refs/docs-design/06-appetite-and-scope.md` — fixed budget and cut order.
- `skill-refs/docs-design/07-plan-and-slices.md` — decision and successor-slice gate.
- `docs/reference/documentation-migration.md` — durable draft-fact ownership.

## Acceptance

```text
When Q-001 through Q-004 close, the project shall record one accepted or rejected workflow decision. -> test/integration/cmd_workflow.bats
If the proposal is rejected, then the milestone surface shall mark slices 003 through 009 `cut` and name the rejection. -> test/integration/cmd_workflow.bats
If the proposal is accepted, then the contract shall enumerate all eleven cells and five invariants without creating runtime data in this slice. -> test/integration/cmd_workflow.bats
```

## Rabbit holes

- Specification expansion can consume the appetite — escape: decide only choices required for the go or no-go contract.
- Current provider rosters can drift during review — escape: treat the seed as proposal input and revalidate before acceptance.

## Done when

The ADR and Q-001..Q-004 exits are recorded. On accept, durable contract facts migrate under that ADR to `docs/reference/` and `docs/explanation/`, and this plan keeps only pointers. On reject, the migration ledger records that those facts died with the proposal and names slice 002 as their last reader.

## Revisions

None.
