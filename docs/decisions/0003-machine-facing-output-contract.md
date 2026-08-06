# ADR-0003: Make machine-facing output the default

<!-- markdownlint-configure-file { "MD043": { "headings": ["# ADR-0003: Make machine-facing output the default","## Context and Problem Statement","## Considered Options","## Decision Outcome","## Consequences","## Status"] } } -->

## Context and Problem Statement

Agent workflows need output that can be parsed without scraping decorative terminal prose. Diagnostics must remain separate from result data.

## Considered Options

- Human-oriented output by default
- Structured stdout with diagnostics on stderr
- Log-only results

## Decision Outcome

Chosen option: `Use structured stdout with diagnostics on stderr` — it gives callers a stable contract and keeps optional human UX additive.

## Consequences

- Automation can compose commands reliably.
- Commands must preserve exit and stream discipline.

## Status

Implemented

Enacted by [CLI runtime](../explanation/cli-runtime.md) and [`fn_ui_print.sh`](../../lib/functions/fn_ui_print.sh).
