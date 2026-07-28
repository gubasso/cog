# ADR-0062: Bootstrap refreshes reviewed templates and reconciles by default

## Context and Problem Statement

`/bootstrap` silently skips any domain already present in the target (e.g. an existing `.pre-commit-config.yaml`), so it never researches newer hooks, refreshes the shipped template, or reconciles improvements into the project. The defect is the orchestrator scope gate (`present=false` is the only scope), not the workers, which already carry research/reconcile prose that never runs for present domains. Users expect every run to keep templates current and bring the target up to date.

## Considered Options

- Keep the present/missing gate; re-run present domains only on explicit destructive opt-in.
- Dispatch every non-opted-out domain by default, gating research behind a freshness cache.
- Add a separate "refresh" command the operator runs by hand.

## Decision Outcome

Chosen option: **dispatch every non-opted-out domain by default** — the audit assigns each domain a `default_action` (`present=false` → `install`, `present=true` → `reconcile`); example intent orients but never shrinks scope.

- Each worker runs a freshness-gated template review before reconcile: stale/missing → current research + shared-template update when justified + a `research-shelf` stamp; fresh → reuse the cached summary. Default freshness window **N = 14 days**.
- Justified improvements dual-write to the target **and** `skill-refs/templates/<domain>/`. Installed-mode (`origin=xdg`) template writes are allowed but every command/summary surfaces the resolved skill-refs root, its origin, and changed template paths — never a silent lossy mutation.
- The plan-mode gate does **not** apply to `bootstrap` (reserved for `executor-*`/`runner-*`).

## Consequences

- Good: present domains are no longer silently skipped; repeat runs stay cheap via shelf freshness.
- Bad: end-user installs can accumulate local uncommitted template-SoT mutations (made visible in machine output and summaries).

References (does not supersede) ADR-0004, 0008, 0016, 0019, 0023, 0061; refines how bootstrap mutates the ADR-0023 template SoT.

## Status

Accepted (2026-07-04)
