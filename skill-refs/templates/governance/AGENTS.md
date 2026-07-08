# Agent Guidelines — {{PROJECT_NAME}}

This file is the single source of truth for how agents work in this project. `CLAUDE.md` imports it
with `@AGENTS.md`, so both Claude Code and the `AGENTS.md`-native tools (Codex, Cursor, and others)
read one authored document.

<!-- self-containment -->
## Self-Containment

Non-negotiable: this project is self-contained. The knowledge it depends on is held in-repo. An
external reference is allowed only as a public external link or citation for further reading, never
as a load-bearing internal dependency: if an external document is required to understand, build, or
operate this project, copy its essential knowledge into the repository (a doc, an ADR, or an inline
comment) so the repo stays complete on its own.

## Decisions

Non-negotiable: record every significant, hard-to-reverse decision as an ADR under `docs/decisions/`,
one decision per file, using the MADR-minimal `template.md`, so the rationale lives with the code.
Accepted ADRs are not deleted; a changed decision gets a new superseding ADR.

## Working Conventions

- Keep changes scoped and reversible; prefer editing existing files over adding new ones.
- Documentation and rationale live beside the code they describe.
- Run the project's own lint and test tasks before proposing changes.
