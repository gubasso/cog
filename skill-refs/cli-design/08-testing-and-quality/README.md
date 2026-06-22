# 08 — Testing & Quality

> Part of the general [CLI design principles](../README.md).

Testing strategy, per-language tooling, regression safeguards, and code quality gates. This chapter
covers **what** to test, **how** to test it, what tools to use, and how to prevent regressions from
both human and AI coding agents.

## Chapters

| Chapter                                           | Question it answers                                                                                       |
| ------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| [Testing strategy](testing-strategy.md)           | "What does the test pyramid look like for a CLI? What goes in each tier? How do I keep tests isolated?"   |
| [Testing tools](testing-tools.md)                 | "Which runner, snapshot library, property framework, and mutation tool should I use for my language?"     |
| [Regression safeguards](regression-safeguards.md) | "How do I prevent AI agents (and humans) from introducing regressions? What's the verification workflow?" |
| [Code quality tools](code-quality-tools.md)       | "Which tools enforce complexity limits, catch unused deps, track binary size, and guard architecture?"    |

Read in this order: strategy first (principles), then tools (implementation), then safeguards
(workflow), then quality tools (structural gates).

## When you need this chapter

- You are setting up tests for a new CLI project.
- You are reviewing or improving an existing test suite.
- You are integrating AI coding agents into your workflow and want guardrails.
- You need to add mutation testing, property-based testing, or complexity enforcement.
- You are configuring pre-commit / pre-push / CI quality gates.

## See also

- [General CLI design index](../README.md)
- [00 — Architecture](../00-architecture.md) — where `tests/`, `support/`, and `snapshots/` sit.
- [04 — Coding Style](../04-coding-style-rust-zig.md) — strict lints, module size caps.
- [05 — Designing for LLM Agents](../05-designing-for-llm-agents.md) — agent-specific test hazards.
- [99 — Checklist](../99-checklist.md) — testing and quality sections.
- Language-specific guides:
  - [`rust/cli-spec/06-testing-and-quality/`](../../../languages/rust/cli-spec/06-testing-and-quality/)
  - [`python/cli-spec/`](../../../languages/python/cli-spec/)
  - [`bash/cli-spec/`](../../../languages/bash/cli-spec/)
