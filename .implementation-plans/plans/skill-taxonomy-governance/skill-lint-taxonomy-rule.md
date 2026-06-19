# Round 2: cog skill-lint prefix-taxonomy rule

> Plan: skill-taxonomy-governance | Round: 2 of 3 | Complexity: M | Generated: 2026-06-19 |
> Repo: /workspaces/cog | Executor: prex (EF 1.5)

## Context

Make the taxonomy enforceable, not just documented. `cog skill-lint`
(`lib/commands/cmd_skill_lint.sh` + `cog::fn::skill::*` helpers in `lib/functions/`) already
hard-fails structural issues and scans orchestration/premise rules. Add a deterministic
`skill-prefix-taxonomy` rule that flags a skill whose prefix disagrees with what it declares it does.

## Previous Rounds

Round 1 recorded the taxonomy ADR + skill-contract "Prefix taxonomy" section + AGENTS/CLAUDE rule.
This round wires the lint enforcement those docs forward-reference.

## Scope of This Round

**IN scope:**

- Add a `cog::fn::skill::classify_prefix` helper (in `lib/functions/`, e.g. extend the existing skill
  helper file) that maps a skill name to its taxonomy class by prefix (`plan-`/`review-`/`executor-`/
  `runner-`/other) and exposes the declared-intent signals already present in a `SKILL.md` (the
  `<!-- cog-skill: plan-emitter -->` marker; presence of an Orchestrator Invocation Contract; etc.).
- Add a `skill-prefix-taxonomy` rule to `cog skill-lint`: a plan-emitting Claude skill (carries
  `<!-- cog-skill: plan-emitter -->`) must be named `plan-*`; a plan-reviewer must be `review-plan-*`;
  keep enforcement conservative (warn vs hard-fail per the existing rule conventions). Preserve the
  existing parent-dir-must-match-`name` check.
- Support a `superseded-by: <skill-name>` metadata marker so a grandfathered misprefixed legacy skill
  (`prex`, `plan-reviewer`) stops failing once its replacement is declared — the migration path the
  dependent siblings use.
- Update `test/integration/cmd_skill_lint.bats` with allowed/rejected name cases and the
  grandfather/`superseded-by` path. Keep `cog::fn::skill::allowed_lint_suppressions_json` /
  `allowed_frontmatter_keys_json` consistent if the marker set changes (mirror the bats expectations).

**OUT of scope:**

- The ADR/reference text (Round 1).
- Actually renaming `prex`/`plan-reviewer` (dependent siblings); this round only makes the rule
  tolerant of the in-progress state.

## Deterministic vs Probabilistic

- Deterministic (cog): the classification helper + the lint rule + bats — all of it.
- Judgment: how aggressively to fail vs warn for each violation class (follow existing skill-lint rule
  conventions; document the choice in the rule's help text).

## Validation

- `test/integration/cmd_skill_lint.bats` green. `cog skill-lint` still passes on every currently
  shipped `SKILL.md` (the legacy `prex`/`plan-reviewer` are grandfathered, not failing).
- Command-surface mirrors only if a new flag/subcommand is added (none expected — this is a new rule
  inside an existing command). `just lint` + `just test` (integration hook) green.

## Execution Discipline

One round per `/prex` session; flip `done` and stop. Commit with `/gc -a` afterward.
