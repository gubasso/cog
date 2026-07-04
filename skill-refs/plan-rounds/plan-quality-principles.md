# Plan-quality principles

The single source of truth for the *quality of a plan's content* — both the driver a `plan-*` emitter
writes toward and the reference a `review-plan-*` skill checks against. It is stage-agnostic and
format-agnostic: it governs what a plan must contain, not which template renders it. Resolve it at
point of use with `cog skill-refs path plan-rounds/plan-quality-principles.md`.

A plan for an AI agent is not a project-manager summary. It is an **execution interface**: the artifact
that lets a fresh context recover intent, locate the exact working surface, change the system in
dependency order, and prove the result. Plans are therefore **lean in format and maximal in depth** —
lean format never licenses shallow content. When depth exceeds one session, the answer is to split into
fresh-context rounds (`cog skill-refs path plan-rounds/round-splitting-contract.md`), never to summarize
the detail away.

## Principles

### 1. Concrete over abstract

Point at the real working surface: exact files, functions, commands, data formats, and expected
signals. "Modify `lib/commands/cmd_x.sh` and run `just test`" beats "update the CLI and test it."
Include the file, command, invariant, and expected signal; omit background that does not affect
execution. Useful density is exact, not verbose.

Concreteness defeats two failure modes: **search drift**, where the executor burns context
rediscovering facts the planner already knew, and **plausible completion**, where the executor changes
something adjacent to the requested behavior but cannot prove the user-visible outcome.

### 2. Machine-checkable acceptance criteria

Each criterion is independently verifiable, phrased Given-When-Then or EARS-style so a precondition,
action, and observable outcome bind into one checkable statement. A criterion two readers could
disagree about passing is not yet a criterion.

```text
- [ ] (R7) GIVEN a queue file with one todo round, WHEN `cog runner-plan next --json` runs,
      THEN the selected round path is returned and no later round is selected.
- [ ] (R8) WHEN `just test` runs, THE SYSTEM SHALL pass the unit and integration hooks.
```

### 3. Requirement traceability

Every criterion carries its `cog round-req`-stamped `R<n>` ID. The ID lets a requirement move through a
split, appear in a round, and be checked at completion without relying on prose similarity. IDs are
allocated by `cog round-req stamp` and preserved across any split (`cog round-split coverage`).

### 4. End-to-end verification gate

Each round ends with a gate that proves it from the closest caller boundary — a CLI command, an HTTP
request, a UI flow, a generated artifact, or a lint rule now passing. Unit tests help, but the gate is
what tells the next fresh executor whether the previous round produced durable evidence or only intent.
Make it explicit enough to run without asking: required setup, exact command, expected output, and what
to do if the gate cannot run.

### 5. Explicit scope and out-of-scope

State what the round delivers and what it defers or excludes. Out-of-scope is an execution control, not
defensive prose: it stops an agent from "helpfully" refactoring nearby systems, broadening tests beyond
the requested contract, or doing later-round work early.

### 6. One-session sizing via fresh-context rounds

Right-size each round to complete in one session with evidence. A single session has practical limits —
attention, tool latency, verification cost, recovery after interruption. The response to oversized
scope is not a shallower plan; it is a full parent plan split into fresh-context rounds, each
self-contained with its own context, scope, steps, acceptance criteria, and verification gate.

### 7. Exhaustive about targets, heuristic about reasoning

Be maximal on the nouns an executor acts on (files, commands, criteria, boundaries); give strong
heuristics rather than brittle micro-scripts for *how* to reason. This is what resolves the
lean-format/maximal-depth tension: stable headings and exact commands with no decorative prose, while
every required step, file, dependency, edge case, and verification signal is present.

A plan that says "implement the remaining handlers" is short but weak. A plan that names every handler,
the shared helper it uses, the queue status change, and the command that proves the flow is longer but
safer. If that detail exceeds one session, split it into rounds and preserve the traceability rather
than compressing it into a summary.

## How this composes

- `plan-*` emitters satisfy these principles in the plan they write; the round artifact structure that
  carries them is Template A in `cog skill-refs path plan-rounds/round-templates.md`.
- `review-plan-*` skills check a plan against these principles — chiefly traceability, verifiable
  criteria, and a runnable verification gate.
- The authoring contract points `plan`/`review-plan` skill authors here from
  `cog skill-refs path skill-authoring/skill-class-contracts.md`.

## Sources

These principles converge across independent primary sources; the research record and revalidation
cadence live in the `cog research-shelf` (topic tag `plan-quality`).

- Anthropic — Claude Code best practices: <https://code.claude.com/docs/en/best-practices>
- Anthropic — Effective context engineering for AI agents:
  <https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents>
- GitHub — Spec Kit: <https://github.com/github/spec-kit>
- AWS — Kiro specs: <https://kiro.dev/docs/specs/>
- BrainGrid — Spec-driven development: <https://www.braingrid.ai/blog/spec-driven-development>
- Addy Osmani — How to write a good spec: <https://addyosmani.com/blog/good-spec/>
- Galileo — Agent failure modes: <https://galileo.ai/blog/agent-failure-modes-guide>
