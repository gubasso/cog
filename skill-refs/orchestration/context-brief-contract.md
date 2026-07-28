# Context-Brief Contract

The general input convention for every input-builder: the structural shape of the **best-constructed input** an orchestrator hands to a worker. The goal is the input that lets the worker produce its best work — a strong, well-oriented brief that carries the full substance and artifacts of the session, kept unbiased — not a raw transcript and not a lossy summary.

A brief is plain markdown delimited by collision-proof section anchors. `cog context-brief` owns the deterministic mechanics — `scaffold` emits the authored skeleton, `build` injects the raw request and assembles the file, and `validate` fails closed unless every section is present and filled. The judgment of what to put in each section is the coordinator's.

## Sections

Every brief carries these sections, in order. Each is introduced by an anchor of the form `<!-- cog:context-brief:section=<key> -->` followed by its `## Heading`.

| Key                 | Heading              | Content                                                                                                                                                                  |
| ------------------- | -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `original-request`  | Original Request     | The user's task prompt(s) for this work, attached as-is. `build` injects this from a rawfile so the raw ask is always present.                                           |
| `objective`         | Objective            | A well-oriented statement of the goal, crafted from the whole session — not just the last message.                                                                       |
| `output-format`     | Output Format        | The exact result/output contract the worker must produce.                                                                                                                |
| `boundaries`        | Boundaries / Scope   | What is in and out of scope, and what not to re-litigate.                                                                                                                |
| `context-decisions` | Context & Decisions  | Substantive background: decisions and rationale, research, findings, and thinking. Summarize narrative for clarity, but carry the full substance that bears on the work. |
| `artifacts`         | Artifacts & Pointers | Generated plans, documents, and code excerpts inline when load-bearing; absolute-path pointers for large or external artifacts.                                          |
| `effort-guidance`   | Effort Guidance      | How much depth and effort the worker should spend.                                                                                                                       |
| `not-evaluated`     | Not Evaluated        | Fields or areas deliberately skipped or not yet evaluated, named explicitly; when none, say so.                                                                          |

## Best-constructed, not lossy

Summarize for orientation and clarity, but pass the full content where it is necessary. A real session accumulates context, decisions, research, findings, and often a generated plan; a prompt like "given this context, implement this" depends on all of it. Carry that substance — never drop a decision or a generated artifact to be terse. When something has no perfect section, place it in the closest one rather than omitting it.

## The single deliberate omission

The coordinator's own verdict or proposed solution is left out. The worker forms an independent judgment from the request, objective, and context; seeding it with the coordinator's conclusion defeats the bias isolation that makes a fresh-context worker valuable.

## Pointers for large or external artifacts

Large artifacts are referenced by absolute path so the worker retrieves them on demand, keeping the brief focused. Use paths reachable in the worker's sandbox; inline the generated plans and excerpts that are load-bearing rather than forcing a fetch.
