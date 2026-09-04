# Script Extraction

> The standard for deciding what stays prose in `SKILL.md` and what moves into a script the skill calls.

## Why extract at all

A `SKILL.md` body is read in full on every invocation. Inline shell therefore costs load-time tokens every time the skill fires, whatever the run does with it. "It runs once" is irrelevant, because the cost is paid at load, not at call.

Moving that shell into a script buys three things:

1. **Tokens.** The body shrinks to a few invocations and the contract they emit.
2. **Determinism.** A script runs byte-identically every time. Shell the model retypes from prose can drift between runs. A file on disk cannot.
3. **Testability.** A script has a test suite. Inline prose-shell never can.

The old rule was to extract only what two or more skills share. That rule is superseded. Single use is fine. The bar is determinism and non-triviality, not reuse count.

## The extraction rule

**Extract any chunk that is deterministic and more than a trivial one-liner.** Four guardrails stop the rule from overshooting.

1. **Split a judgment-tangled chunk. Do not move it whole.** Extract the deterministic half: exit code to status classification, severity to label mapping, file scaffolding, flag parsing, structured parsing, validation. Keep the decision as prose. Keep the seam clean.
2. **Keep a trivial one-liner inline.** A single existence check or a single field read costs more to wrap than it saves.
3. **Be coarse, not micro.** Write a few scripts that each do a meaningful unit and emit one structured object the body reads a few fields from. Do not write a cloud of micro-helpers stitched together with parsing between each call, because that trades shell tokens for plumbing tokens.
4. **Prompt content stays model-authored.** Extract the scaffolding only: writing the file, setting the flags, preparing the directory. The natural-language text the skill passes to another agent is data the model writes, not something a script hard-codes.

## Worked judgment calls

| Chunk                                                                | Verdict     | Reason                                           |
| -------------------------------------------------------------------- | ----------- | ------------------------------------------------ |
| A 30-line preflight that parses tool health and exits when unhealthy | Extract     | Deterministic, repeated, fails closed legibly    |
| A single field read from a result object                             | Keep inline | Trivial single read                              |
| A table mapping a finding to a triage status                         | Keep prose  | Reads deterministic input but encodes a decision |
| Scratch directory plus output path scaffolding                       | Extract     | Pure scaffolding, identical every run            |

## What a script must do

- Run without a terminal. It must never prompt.
- Bound its output. A script that can emit unbounded text truncates and says so.
- Fail with a legible message that names the cause and the fix.
- Return a meaningful exit code. Reserve distinct codes for distinct outcomes.
- Default to the safe action.
- Be idempotent where the task allows it.
- Offer a dry-run mode when it changes or deletes anything.

## Reporting results

Separate the two audiences. Write the machine-readable result to standard output. Write human progress and diagnostics to standard error. A caller can then parse the result without stripping prose out of it.

When a script bounds its coverage — a top-N cap, sampling, or no retry — it must say so on standard error. A silent cap reads as "covered everything" when it did not.

## Declaring a dependency

A skill that calls a tool must declare it, check for it, and fail legibly when it is absent.

Separate a hard dependency from a soft one. A hard dependency blocks the run. A soft dependency degrades one feature, and the skill continues with the feature disabled and says which feature it disabled.

## Scratch space

A skill that needs intermediate space creates it outside the user's project, and writes every intermediate artifact under it.

```bash
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
```

Deliverables are out of scope for this rule. A file the skill exists to produce goes to its real destination in the user's project. Only scratch and intermediate artifacts belong in the working directory.

## Anti-patterns

Do not do any of the following:

- **Extract a trivial single read.** Keep it inline.
- **Extract a prompt body.** Content is model-authored. Only scaffolding extracts.
- **Extract a judgment table.** A table that reads deterministic input but encodes a decision stays prose.
- **Write a micro-helper cloud.** Several scripts stitched with parsing between each call. Make it coarse: one script, one result object.
- **Truncate silently.** Say what the bound was.
- **Hand-roll a fallback for a missing tool.** Call the tool and check for it. Do not carry a second, stale implementation.
