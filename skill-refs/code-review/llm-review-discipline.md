# LLM Review Discipline

Rules for keeping findings evidence-grounded and the false-positive rate low when an LLM is
reviewing code. Synthesized from contemporary research on LLM-assisted code review (see
**References** at bottom).

## The headline rule

> **Every finding must cite a file:line, a quoted snippet, or a docs URL. If you cannot cite
> evidence, downgrade to `[question]`.**

LLMs hallucinate plausible bugs. The cure is mechanical: no claim without a citation, and explicit
downgrade of uncertain claims to questions the author can resolve.

## Findings discipline

For every finding emit a structured record:

```text
[severity] <one-line headline>
  File: <path>:<line-start>[-<line-end>]
  Evidence: <quoted snippet OR observation about what the code does>
  Reasoning: <why this is a problem — 1-3 sentences max>
  Suggestion: <what to do instead — optional but encouraged>
  Confidence: <high | medium | low>
```

Rules:

1. **Evidence is verbatim.** Quote the offending code, do not paraphrase. If the snippet exceeds 10
   lines, link by line range and quote the pivotal subset.
2. **Reasoning names the failure mode.** "This is wrong" is not reasoning. "Concurrent readers can
   observe a half-initialized value because the write to `state` happens after the publish on line
   47" is reasoning.
3. **Confidence is honest.** `low` → demote to `[question]`. `medium` → keep but offer alternatives,
   don't dictate. `high` → reserved for findings you can prove (citation to spec, language ref, or
   tracing the exact failing path in the diff).
4. **No vibes-based criticism.** "This feels off" / "I'd write it differently" is not a finding.
   Either ground it in a rule or drop it.

## False-positive triage

Empirically, hybrid LLM+SA pipelines achieve <20% FP rates only when the LLM's claims are filtered
through a verification step (see Datadog and arxiv references below). Mirror that discipline
manually:

1. After generating each finding, ask: **"What is the minimum input that proves this bug
   triggers?"** If you cannot construct one mentally, the finding is speculative — downgrade.
2. For null-deref / unwrap / panic findings: trace whether the value is provably non-null at the
   call site (constructor invariant, prior check, type system). If yes, drop the finding.
3. For race-condition findings: identify the two threads and the unsynchronized memory access. If
   the access is behind a lock, a channel, or a single-writer invariant, drop.
4. For security findings: identify the source (untrusted input), the sink (dangerous operation), and
   the unsanitized path between them. No path → no finding. This is the source-to-sink reachability
   test from the LLM4PFA literature.

## Source-to-sink reachability (security)

For any security finding, the report must answer three questions:

1. **Source.** Which input is the attacker controlling? Name the parameter or API.
2. **Sink.** Which operation is dangerous? (e.g., `eval`, raw SQL, file path concatenation, shell
   exec.)
3. **Path.** Trace the data from source to sink. Cite each intermediate file:line. If any
   intermediate sanitizer breaks the path, the finding is invalid.

If the path is incomplete or hypothetical, emit `[question]` instead of `[blocking]`.

## Agent-readable output

When the consumer of the review is another agent (Claude, Codex, Aider, Copilot Workspace) or a CI
script:

- Default to **JSON output** (`--format json`). Stable schema; one finding per array element; fields
  match the structured record above.
- Use stable identifiers: `severity`, `file`, `line_start`, `line_end`, `category`, `headline`,
  `evidence`, `reasoning`, `suggestion`, `confidence`. No emoji, no markdown decoration inside field
  values.
- Sort findings by `(severity_rank desc, file asc, line_start asc)` so consumers can stream the
  worst issues first.

When the consumer is human (`--format markdown`, the default):

- Group by file, then by severity.
- Use `code-fenced` snippets for evidence.
- Include the `Confidence: …` line for `medium`/`low` only. Suppress it for `high` to reduce visual
  noise.

## What the reviewer must NOT do

- **Restate the diff.** The reader has access to `git diff`. The review's value is interpretation,
  not narration.
- **Speculate on intent.** "The author probably meant X" — ask via `[question]` instead.
- **Bundle unrelated findings.** One finding = one root cause. Splitting helps the author fix and
  re-push incrementally.
- **Repeat findings across files.** If the same anti-pattern occurs in 5 files, emit one
  meta-finding citing one location + a list of the others. Severity equals the highest individual
  instance.
- **Re-run the linter.** Anything pre-commit / CI lint already covers is dropped from the review
  output. Comment on configuration if the linter should but doesn't.

## Severity calibration

Tiered failure-modes to anchor `[blocking]` vs `[important]` vs `[nit]`:

| Severity       | Trigger                                                                                                                                                                   |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `[blocking]`   | Memory corruption, data loss, auth bypass, panic in main path, broken public API contract, secret in code, CI green ≠ correct (test missing the new branch).              |
| `[important]`  | Resource leak under failure, missing error handling on a fallible call, performance regression in a hot path, missing test for a non-trivial branch, log-format breakage. |
| `[nit]`        | Naming, comment quality, trivial duplication, line length, import order beyond what the linter handles.                                                                   |
| `[suggestion]` | Alternative library, alternative algorithm with comparable trade-offs, refactor for readability.                                                                          |
| `[question]`   | Reviewer cannot determine correctness from the diff alone.                                                                                                                |
| `[praise]`     | Notable design quality, test thoroughness, or clarity improvement.                                                                                                        |

When in doubt between two adjacent severities, take the lower one and explain the trade-off in the
reasoning. Over-flagging trains authors to ignore the label.

## References

- Hou et al.,
  "[An Insight into Security Code Review with LLMs: Capabilities, Obstacles, and
  Influential Factors](https://arxiv.org/pdf/2401.16310)" (2024–) — empirical study; source for the
  FP rate threshold and the source-to-sink discipline.
- Wu et al.,
  "[Reducing False Positives in Static Bug Detection with LLMs: An Empirical Study
  in Industry](https://arxiv.org/pdf/2601.18844)" — industry study showing 94–98% FP reduction with
  structured reasoning prompts.
- Liu et al.,
  "[Utilizing Precise and Complete Code Context to Guide LLM in Automatic False
  Positive Mitigation](https://arxiv.org/pdf/2411.03079)" — LLM4PFA, the path-feasibility framework
  this file borrows from.
- Datadog Security Labs,
  "[Using LLMs to filter out false positives from static code
  analysis](https://www.datadoghq.com/blog/using-llms-to-filter-out-false-positives/)" — practical
  pipeline write-up.
- Anthropic,
  "[Skill authoring best practices](https://docs.claude.com/en/docs/agents-and-tools/agent-skills/best-practices)"
  — the source for progressive-disclosure conventions this skill uses.
