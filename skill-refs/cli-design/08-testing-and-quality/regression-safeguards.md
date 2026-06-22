# Regression Safeguards

Preventing implementation regressions, especially those introduced by AI coding agents. This chapter
defines the two safeguard categories (behavioral and structural), the verification workflow, and the
layering model that determines when each check runs.

For concrete per-language tooling, see the companion file
**[10a — Code Quality Tools](code-quality-tools.md)** and the existing testing references
**[08 — Testing Strategy](testing-strategy.md)** / **[08a — Testing Tools](testing-tools.md)**.

## Why AI agents cause regressions

AI coding agents are non-deterministic. The same prompt can produce structurally different
implementations across runs. The failure modes are predictable:

| Failure mode                | What happens                                                                                                  | Which safeguard catches it                                                      |
| --------------------------- | ------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| **Happy-path-only testing** | Agent writes tests that cover the golden path but miss edge cases, boundary inputs, and error branches.       | Property-based testing, mutation testing.                                       |
| **Mock-only assertions**    | Tests stub every dependency and only assert on the mock's call shape. Project logic is never exercised.       | Mutation testing, third-party-library heuristics (see [08]).                    |
| **Subtle output changes**   | Agent changes a CLI flag name, JSON field, error message, or help text without realizing it's a contract.     | Snapshot testing, golden file testing, contract tests.                          |
| **Complexity creep**        | Agent adds unnecessary abstractions, deep nesting, excessive generics, or over-parameterized functions.       | Complexity metrics, function-length lints, architectural boundary checks.       |
| **Dependency bloat**        | Agent adds crates/packages that aren't needed, or duplicates functionality already in the dep tree.           | Unused-dependency detection, binary size tracking.                              |
| **Leftover scaffolding**    | Agent leaves `todo!()`, `dbg!()`, `unwrap()`, or debug prints in production code.                             | Restriction lints (`clippy::todo`, `clippy::dbg_macro`, `clippy::unwrap_used`). |
| **Performance regression**  | Agent introduces an O(n^2) loop or an unnecessary allocation in a hot path without any benchmark to catch it. | Continuous benchmarking, binary size tracking.                                  |
| **Silent behavior change**  | Agent refactors internal logic and tests pass, but the actual user-facing behavior changed.                   | E2E tests, approval testing, eval harnesses.                                    |

The safeguards below address these failure modes systematically.

## Two safeguard categories

### Category 1: Behavioral guarantees

Tests and checks that verify the program does what users expect. These lock down the **external
contract** — what the program does, not how it does it.

| Technique               | What it locks down                                         | Where documented                                                                                |
| ----------------------- | ---------------------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| Unit tests              | Individual functions and modules behave correctly.         | [08 § Unit tests](testing-strategy.md#unit-tests)                                               |
| Integration tests       | Subcommands produce correct output and side effects.       | [08 § Integration tests](testing-strategy.md#integration-tests--one-per-subcommand)             |
| Snapshot / golden tests | Structured output (JSON, help text, error messages).       | [08 § Snapshot tests](testing-strategy.md#snapshot-tests)                                       |
| E2E / acceptance tests  | The binary works end-to-end against real dependencies.     | [08 § E2E tests](testing-strategy.md#e2e-tests)                                                 |
| Property-based tests    | Invariants hold for all inputs of a shape.                 | [08 § Property-based](testing-strategy.md#property-based-testing)                               |
| Mutation testing        | Tests actually detect changes in production code.          | [08 § Mutation testing](testing-strategy.md#mutation-testing-as-quality-gate)                   |
| Contract tests          | API / CLI output schemas remain stable across versions.    | [08a § Contract testing](testing-tools.md#contract-testing)                                     |
| Argv-contract tests     | Subprocess invocations produce correct argument vectors.   | [08 § Argv-contract](testing-strategy.md#argv-contract-tests-for-clis-that-wrap-other-binaries) |
| Eval harnesses          | AI agent workflows produce correct results over N samples. | [05 § Verification](../05-designing-for-llm-agents.md#5-verification-and-evals)                 |

### Category 2: Structural quality gates

Checks that enforce code quality, complexity limits, and dependency hygiene. These protect against
**how** the code is written — catching overengineering, dead code, and unnecessary dependencies
before they land.

| Technique                     | What it catches                                                | Where documented                                                               |
| ----------------------------- | -------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| Complexity metrics            | Functions that are too long, too nested, or too hard to read.  | [10a § Complexity](code-quality-tools.md#complexity-metrics)                   |
| Restriction lints             | Leftover scaffolding (`todo!`, `dbg!`, `unwrap`), unsafe code. | [10a § Linting](code-quality-tools.md#restriction-lints)                       |
| Unused dependency detection   | Crates/packages added but never imported.                      | [10a § Deps](code-quality-tools.md#unused-dependency-detection)                |
| Security / license auditing   | Known CVEs, license violations, banned dependencies.           | [10a § Security](code-quality-tools.md#security-and-license-auditing)          |
| Binary size tracking          | Unexpected growth from added dependencies or generics bloat.   | [10a § Binary](code-quality-tools.md#binary-size-analysis)                     |
| Architectural boundary checks | Layer violations, unauthorized cross-module imports.           | [10a § Architecture](code-quality-tools.md#architectural-boundary-enforcement) |
| Dead code detection           | Unused functions, types, or modules.                           | [10a § Dead code](code-quality-tools.md#dead-code-detection)                   |
| Code metrics tracking         | LLOC trends, comment ratios, churn analysis.                   | [10a § Metrics](code-quality-tools.md#code-metrics-and-churn-tracking)         |
| Continuous benchmarking       | Performance regressions across commits.                        | [10a § Benchmarks](code-quality-tools.md#continuous-benchmarking)              |

## The layering model

Every check has a cost. Assign each to the tier whose time budget it fits.

```text
PRE-COMMIT  (<30 s)
├── Format check (rustfmt / black / shfmt)
├── Fast lints (clippy / ruff / shellcheck) including restriction lints
├── Stdout/stderr ownership lint
├── Unused dependency detection (cargo-machete / similar)
└── Unit tests (parallel, fail-fast)

PRE-PUSH  (<2 min)
├── Integration tests (parallel)
├── Security / license audit (cargo-deny / pip-audit)
└── Complexity metrics on modified files (fail on threshold breach)

CI — PR  (<10 min)
├── Full test suite (unit + integration + E2E)
├── Snapshot review (new/changed snapshots flagged)
├── Contract tests
├── Binary size comparison vs baseline
├── Code coverage (as floor, not goal)
└── Property-based tests (standard iteration count)

CI — NIGHTLY  (hours OK)
├── Mutation testing on critical modules
├── Property-based tests (extended iteration count)
├── Full complexity analysis (all files, not just modified)
├── Continuous benchmarking (criterion / hyperfine)
└── Precise unused-dep detection (cargo-udeps, requires nightly)
```

**Rules:**

- Each tier is a superset of the previous — nothing skipped, just added.
- Pre-commit must never exceed 30 seconds. If a check is too slow, move it to pre-push.
- Nightly checks are informational, not blocking (unless the team promotes a specific module to
  gated after the score stabilizes).
- The layering is encoded in the justfile / Makefile / task runner and in `.pre-commit-config.yaml`.
  CI invokes the same recipes.
- **Profiles are dead config unless invoked explicitly.** Every CI step, pre-commit hook, and
  pre-push hook must pass the right `--profile` / `--config` flag. This is the most common reason a
  gate silently does nothing. See
  [08a § Tuning test-runner output](testing-tools.md#tuning-test-runner-output-for-ci--ai-agents).

## Test-Driven Development for AI agents

The single most effective safeguard against AI-agent regressions is **writing tests before handing
implementation to the agent**.

### The TDD-for-agents workflow

```text
1. Human writes tests that define the expected behavior (contracts, edge cases, error paths).
2. Human runs the tests — they fail (red).
3. Human hands implementation to the AI agent: "Implement until all tests pass. Do not modify tests."
4. Agent iterates against the test suite (immediate feedback from compiler + test runner).
5. Human reviews the implementation, runs the full quality gate (`just check`).
6. Human verifies mutation score hasn't dropped on the modified modules.
```

**Why it works:**

- The contract is explicit and machine-checkable. The agent can't silently change the specification.
- Rust's compiler gives the agent immediate, precise feedback on type errors and borrow violations.
- The test suite constrains the solution space — the agent can't overengineer when the tests define
  exactly what's needed.
- Human review focuses on quality and style, not correctness — correctness is already verified.

**When to skip it:**

- Exploratory work where the requirements are genuinely unknown.
- Pure refactoring where existing tests already cover the behavior.
- Trivial changes where writing the test takes longer than verifying the change.

Sources:
[Test-Driven Generation](https://chanwit.medium.com/test-driven-generation-tdg-adopting-tdd-again-this-time-with-gen-ai-27f986bed6f8)
·
[Test-First Prompting](https://www.endorlabs.com/learn/test-first-prompting-using-tdd-for-secure-ai-generated-code/).

## Eval harnesses for agent skills

For CLIs that agents consume (or for verifying agent-written code), programmatic evals provide a
regression signal that's distinct from — and complementary to — the test suite.

### What an eval verifies

- **Deterministic checks**: Did the agent call the right commands? Did it pass `--dry-run` before
  committing? Did it use `--json` for machine-parseable output?
- **Rubric-style checks**: Is the final output well-formed? Does it match the expected schema? Did
  the agent follow the documented workflow?
- **Statistical signal**: Over N runs (10+ samples per prompt), what's the pass rate? A single
  sample is meaningless for a non-deterministic system.

### Eval-driven development

Treat eval pass rates like test coverage: track them over time, investigate drops, promote stable
evals to gated. The eval suite is a separate artifact from the test suite — tests verify the CLI
works; evals verify the agent uses the CLI correctly.

Sources:
[OpenAI — Testing Agent Skills Systematically with Evals](https://developers.openai.com/blog/eval-skills)
· [05 § Verification and Evals](../05-designing-for-llm-agents.md#5-verification-and-evals).

## Verification loops

The pattern from
[05 § Validation loops](../05-designing-for-llm-agents.md#36-validation-loops-are-gold), generalized
to agent-written code:

```text
1. Agent writes code.
2. Agent runs `just check` (format, lint, test, audit).
3. If any gate fails, agent fixes and repeats from step 2.
4. When all gates pass, agent reports completion.
5. Human reviews diff, runs mutation testing on modified modules.
6. Human verifies snapshot diffs are intentional.
7. If mutation score dropped or snapshots changed unexpectedly, reject and iterate.
```

The key insight: **agents iterate cheaply against automated gates**. The more precise and fast the
gates, the tighter the feedback loop, and the less human review is needed.

## Anti-patterns

- **Relying on coverage alone.** Coverage says what was executed, not what was checked. Pair it with
  mutation testing for real signal. See
  [08 § Coverage philosophy](testing-strategy.md#coverage-philosophy).
- **Skipping mutation testing because "tests pass."** AI-generated tests are notorious for high
  coverage, low mutation score. The test runs the code but doesn't check the result.
- **No complexity threshold.** Without a complexity gate, AI agents freely introduce deeply nested,
  over-parameterized functions. Set thresholds and enforce them in CI.
- **Trusting snapshot auto-update.** Never auto-update snapshots in CI. Every snapshot change must
  be reviewed. An AI agent that silently changes a JSON schema is introducing a breaking change.
- **One-sample eval runs.** Running an eval once and declaring "it works" is statistically
  meaningless. Run 10+ samples; track the pass rate.
- **No binary size baseline.** Without a baseline, you won't notice when an agent adds a 2MB
  dependency for a 10-line feature.

## Implementation checklist

Add to [99 — Checklist](../99-checklist.md):

- [ ] Property-based tests cover parsers, codecs, newtypes, and state machines.
- [ ] Mutation score (>= 60%) tracked on critical modules; nightly CI.
- [ ] Complexity thresholds enforced in CI (cognitive complexity, function length).
- [ ] Restriction lints enabled (`todo`, `dbg_macro`, `unwrap_used`, `panic`).
- [ ] Unused dependency detection runs in pre-commit.
- [ ] Binary size baseline tracked; CI flags growth > 5%.
- [ ] Snapshot updates require explicit review (never auto-updated in CI).
- [ ] TDD-for-agents workflow documented in CLAUDE.md / AGENTS.md.
- [ ] Eval harness exists for agent-consumed CLI skills (10+ samples per prompt).

## See also

- [08 — Testing Strategy](testing-strategy.md) — the testing pyramid and principles.
- [08a — Testing Tools](testing-tools.md) — per-language testing tool matrix.
- [10a — Code Quality Tools](code-quality-tools.md) — per-language quality gate tool matrix.
- [05 — Designing for LLM Agents](../05-designing-for-llm-agents.md) — CLI design for agent
  consumption.
- [04 — Coding Style](../04-coding-style-rust-zig.md) — strict lints, module size caps.
- [99 — Checklist](../99-checklist.md) — one-page sanity check.
- Language-specific guides:
  - [`rust/cli-spec/06a-advanced-testing.md`](../../../languages/rust/cli-spec/06-testing-and-quality/advanced-testing.md)
  - [`rust/cli-spec/06b-code-quality.md`](../../../languages/rust/cli-spec/06-testing-and-quality/code-quality.md)

## References

- [Test-Driven Generation (TDG)](https://chanwit.medium.com/test-driven-generation-tdg-adopting-tdd-again-this-time-with-gen-ai-27f986bed6f8)
- [Test-First Prompting (Endor Labs)](https://www.endorlabs.com/learn/test-first-prompting-using-tdd-for-secure-ai-generated-code/)
- [SWE-Bench Verified](https://www.swebench.com/verified.html) — industry benchmark for agentic
  coding
- [DeepEval — AI Agent Evaluation](https://deepeval.com/guides/guides-ai-agent-evaluation)
- [Red Hat — Eval-Driven Development](https://developers.redhat.com/articles/2026/03/23/eval-driven-development-build-evaluate-ai-agents/)
- [Stryker — Mutation Testing Intro](https://stryker-mutator.io/docs/)
- [Martin Fowler — Practical Test Pyramid](https://martinfowler.com/articles/practical-test-pyramid.html)
