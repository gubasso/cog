# ADR-0029: Merge bootstrap workers that share a decision

## Context and Problem Statement

The bootstrap family had twelve skills and ~1,350 lines, and two of its splits cost more than they bought.

`bootstrap-editorconfig` and `bootstrap-precommit` wrote two files that are only correct when they agree — an `editorconfig-checker` hook that contradicts the project's formatter is worse than no hook. Keeping them apart forced a dispatch ordering ("precommit reads the established `.editorconfig` baseline") and left the agreement unverified by anything.

`bootstrap-cargo-publish` could not fix a crates.io metadata gap it detected, because `Cargo.toml` belonged to `bootstrap-rust`. It surfaced gaps as fragments for another worker to apply, and the orchestrator had to dispatch it after `bootstrap-rust` "so the crate exists".

Both splits made one decision travel across a context boundary as a hand-off.

## Considered Options

- Merge the two pairs, keeping the `bootstrap-audit` domains unchanged.
- Keep every worker one-to-one with a domain and formalize the hand-offs.
- Merge more aggressively (fold `ci`, `taskrunner`, and `installer` together too).

## Decision Outcome

Chosen option: `merge the two pairs` — the boundary belongs where a decision ends, not where a file does. `bootstrap-lint` owns code-style configuration; `bootstrap-rust` owns the crate and its publishing branch.

The `cog bootstrap-audit` domain names stay unchanged: domains are artifact-presence facts, wired into `cmd_bootstrap_template_review.sh` and `fn_bootstrap_review.sh`, and nothing about the merge changes what is present on disk. Fewer skills, zero CLI churn.

Because skill-lint derived a worker's domain from its name, the merges would have silently dropped freshness tracking for `editorconfig` and `cargo-publish`. `cog::fn::bootstrap_review::skill_domains` now maps a skill to the domains it owns, and skill-lint reads that instead.

## Consequences

- Good: two dispatch dependencies disappear; the family drops to ten skills and ~790 lines.
- Good: `bootstrap-rust` fixes metadata in place instead of describing gaps to another agent.
- Bad: `bootstrap-lint` owns two artifacts, which bends the "one domain per `bootstrap-*` skill" line in the skill contract. Code-style configuration is read as one domain with two files.
- Bad: a merged worker's context is larger, so a run touching only `.editorconfig` loads the hook prose too.

## Status

Implemented

Enacted in [bootstrap-lint](../../skills/claude/bootstrap-lint/SKILL.md), [bootstrap-rust](../../skills/claude/bootstrap-rust/SKILL.md), and [fn_bootstrap_review](../../lib/functions/fn_bootstrap_review.sh).
