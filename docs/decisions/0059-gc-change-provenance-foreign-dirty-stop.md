# ADR-0059: gc change-provenance foreign-dirty STOP

## Context and Problem Statement

A `/gc` run nearly destroyed pre-existing user work (forensic record: `.draft/postmortem-gc-known-issues-session.md`). `gc` assumed the dirty working tree belonged entirely to the current session; whole-file staging swept an undeclared feature's hunks into the commit, and improvised `git reset`/`restore` recovery then deleted a second feature's source. `cog gc-plan` already computes `extra_dirty` (dirty/untracked paths the session did not declare) from a live `git status`, but treated it as benign — there was no change-provenance gate.

## Considered Options

- Promote `extra_dirty` to a `surprises` hard STOP, reusing the existing safety-scan halt.
- Add a new `cog gc-attribute` command that classifies each dirty file as own/foreign/mixed.
- Leave detection to skill prose/model judgment only.

## Decision Outcome

Chosen option: **promote `extra_dirty` to a `foreign-dirty:<root>` `surprises` entry, default-on** — it reuses the STOP the skill already honors, fires before any staging, and defeats the stale-baseline root cause mechanically (gc-plan recomputes from live status every call). Rejected a separate `gc-attribute` command: it would duplicate the partition logic gc-plan already has, and intra-file mixing of a _declared_ file is not mechanizable from git history alone. `gc` is promoted from the `cheap`/haiku tier to `low` (`opus`, `effort: low`) so the added diffstat materiality check is sanctioned bounded judgment. Layered prose in both twins adds: a destructive-recovery prohibition

- stop-the-line tripwire, a fresh-baseline step, a `git diff --cached --stat` mixed-file tripwire, and a whole-file-staging caveat.

## Consequences

- Good: the incident chain is broken at a deterministic gate independent of model discipline.
- Good: hard STOP surfaces any undeclared dirty/untracked file for an explicit user decision.
- Bad: benign stray/untracked files now STOP by default; relieved by declaring them or `--all` (which unions `extra_dirty` into the session list and re-runs).
- Acknowledged gap: intra-file mixing with no other undeclared dirt is caught only by the diffstat tripwire, not the mechanical gate.

## Status

Implemented — `lib/commands/cmd_gc_plan.sh` (`__cog_gc_plan_build_json`), `data/model-effort/claude/tiers.yaml`, `skills/claude/gc/SKILL.md`, `skills/codex/gc/SKILL.md`, `skills/claude/gc-hook-fix/SKILL.md`; tests in `test/unit/cmd_gc_plan.bats`, `test/integration/skills_claude.bats`, `test/integration/cmd_skill_lint.bats`.
