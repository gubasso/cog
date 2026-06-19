# Round 2: Official Claude Code + Codex docs research

> Plan: skill-research-shelf | Round: 2 of 3 | Complexity: M | Generated: 2026-06-19 |
> Repo: /workspaces/cog | Executor: prex (EF 1.5)

## Context

Run the dedicated web-research pass over OFFICIAL sources and persist it once, so every downstream
skill reuses it. This is the research the user asked for ("look for official docs/specs of claude
code, claude code skills … codex cli, codex cli skills").

## Previous Rounds

Round 1 built the `cog research-shelf` store + schema.

## Scope of This Round

**IN scope:**

- Web research, official-first, covering: Claude Code official docs/specs; Claude Code skills
  authoring/spec (frontmatter keys, plan mode semantics, slash-command invocation); Codex CLI official
  docs/specs (exec/resume, sandbox modes, `model_reasoning_effort` / effort options); Codex skill
  behavior and invocation constraints.
- Persist each finding via `cog research-shelf record` with title/url/publisher/access-date, a stable
  summary, topic tags, a revalidation cadence, and the consuming-skills list (plan-claude, plan-codex,
  review-plan-*, executors).
- Cross-check against the in-repo SoT already present (`docs/reference/skill-contract.md`,
  `model-effort-policy.md`, and the codex-conventions maintenance doc) so the shelf does not contradict
  the repo's own contracts; note any divergence as a finding.

**OUT of scope:**

- Best-practice/community patterns (Round 3).
- Editing any skill body (consuming siblings).

## Deterministic vs Probabilistic

- Deterministic (cog): persistence + validation via `cog research-shelf record`/`validate`.
- Judgment: which sources are authoritative, what to summarize, currency assessment.

## Validation

- `cog research-shelf validate` passes; every recorded entry is dated and sourced. No live URLs or
  research prose leak into any `SKILL.md` (shelf-only). `just lint` green on the touched docs.

## Execution Discipline

One round per `/prex` session; flip `done` and stop. Commit with `/gc -a` afterward.
