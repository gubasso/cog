# Workflow contract

The accepted grammar, engine registry, and validator rules for the cog workflow engine. [ADR-0027](../decisions/0027-accept-the-workflow-engine.md) accepted this contract; [ADR-0023](../decisions/0023-select-workflow-engines-at-definition-or-call-site.md), [ADR-0024](../decisions/0024-pass-step-artifacts-by-directory.md), [ADR-0025](../decisions/0025-needs-is-the-only-edge-directive.md), and [ADR-0026](../decisions/0026-judge-loop-convergence-with-a-prose-criterion.md) own the choices behind it.

Nothing here is implemented yet. The first code lands in slice 003; the verb grammar and exit-code protocol stay in that slice until [CLI commands](./cli-commands.md) owns them.

## Workspace layout

```text
workflow/
  meta.yaml     three closed defaults: context, max_rounds, max_workflow_depth
  workflows/    composite definitions; no skill: key anywhere
  steps/        leaf definitions; the only files that may carry skill:
  skills/       the prose the agents read
```

The unit of layer resolution is the file, not the root. One resolver walks project, then user, then installed, and returns the first file that exists, taken whole. Nothing is merged, so a project-layer workflow replaces the installed one entirely rather than inheriting its steps.

## Call forms

A workflow's `steps:` is a list. Each entry carries exactly one kind key, and that key discriminates leaf from composite at the call site.

| Kind key    | What it is             | Keys it takes                                 |
| ----------- | ---------------------- | --------------------------------------------- |
| `step:`     | leaf; runs a skill     | `id`, `as`, `engine`, `needs`                 |
| `workflow:` | composite by reference | `id`, `as`, `needs`                           |
| `loop:`     | composite inline       | `as`, `needs`, `until`, `max_rounds`, `steps` |

`needs:` is the only edge key. It points at siblings, never crosses a scope boundary, and is never a call. It carries both execution order and mutual exclusion: two steps that must not overlap get an edge between them.

## Name spaces

`id:` names the definition, is unique within its directory, and resolves to a file. `as:` names this instantiation, is unique within the DAG, and is what `needs:` targets. `as:` defaults to `id:`, so only fan-out pays for the distinction.

## Engines

An engine record carries exactly four fields.

```yaml
- id: codex-gpt-5.5-high
  provider: codex
  model: gpt-5.5
  effort: high
```

`engine:` is required on a step definition and optional on a call site, where it overrides the definition for that call only. Values are file literals in both positions, never expressions. A `workflow:` or `loop:` node carries no engine key, because it runs no agent. A call site overrides only the step it calls and never reaches into a referenced workflow's interior, so there is no precedence rule to state.

Effort ladders differ by provider, and ordering is meaningful within a provider and undefined across providers.

| Provider | Efforts, weakest to strongest                   |
| -------- | ----------------------------------------------- |
| `claude` | `none`, `low`, `medium`, `high`, `xhigh`, `max` |
| `codex`  | `minimal`, `low`, `medium`, `high`, `xhigh`     |

The accepted seed is eleven engines: `claude-haiku-4.5-none`; `claude-opus-4.8-low`, `-medium`, `-high`, `-xhigh`, `-max`; and `codex-gpt-5.5-minimal`, `-low`, `-medium`, `-high`, `-xhigh`. Membership in the registry is the permission; an engine that cannot be run is a row that does not exist rather than a row with a false flag.

Five registry invariants hold: derived ids, unique ids, exactly four fields, provider-valid efforts, and an existing provider runner.

## Artifacts

Each step writes its artifacts into its own directory under the run directory. `needs:` hands every upstream directory to the step that depends on it.

```yaml
steps:
  - step: {id: plan,   as: draft}
  - step: {id: review, as: vet,   needs: [draft]}
  - step: {id: apply,  as: apply, needs: [draft, vet]}
```

```text
$RUN_DIR/
  draft/     plan.md writes here
  vet/       receives ../draft/
  apply/     receives ../draft/ and ../vet/
```

A step file may describe the inputs it expects and the artifacts it produces. That description is aligned against its skill at lint time and is never enforced at run time. The skill owns what it reads and produces.

## Loops

`until:` and `max_rounds:` are both required. `until:` is a prose criterion cog stores and never parses. At each round boundary the orchestrator reads the criterion and the round's directories, then reports its decision; cog materializes round N+1 only on that call, one round at a time.

An `until:` criterion should be applicable by a reader to the round's artifacts, and should describe the stall path as well as the success path.

`max_rounds:` is a hard ceiling enforced before a round is materialized, and reaching it is a failure rather than a success. A round that produced no files refuses to continue or converge.

A loop is a runtime scope, not a resolve-time expansion. Composites flatten statically into dotted sibling handles; a loop resolves to one node carrying an unexpanded but fully validated template. A loop's output directory is its last completed round's.

## What the grammar does not have

Recorded so it is not re-proposed: no `if:` and no conditional of any kind, so every node in the run graph runs and the join question never arises; no `matrix:`; no fold operator, with `combine:` reserved for [power grade](../explanation/power-grade.md); no `for_each:`, because unknown cardinality lives inside a step whose skill prose owns its loop; no `sync:` marker; and no expression language.

## Validator rules

Validation runs once at load, before any agent is spawned, so a failure does not land at depth three after real spend.

- Exactly one kind key per entry.
- `as:` unique within a DAG, and every `needs:` target present in it.
- No cycle among `needs:` edges, and none across file references.
- `engine:` a literal present in the registry, required on every step definition, optional on a call site.
- `loop:` carrying both `until:` and `max_rounds:`.
- `id:`, `as:`, `engine:`, and `until:` parsed as strings, which closes the YAML scalar footguns; `until:` also non-empty.
- `max_rounds:` a positive integer.
- Reference nesting within `max_workflow_depth`.
- No `skill:` key anywhere under `workflows/`.
