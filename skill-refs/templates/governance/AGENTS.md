# Agent Guidelines — {{PROJECT_NAME}}

This file is the single source of truth for how agents work in this project. `CLAUDE.md` imports it
with `@AGENTS.md`, so both Claude Code and the `AGENTS.md`-native tools (Codex, Cursor, and others)
read one authored document.

<!-- self-containment -->
## Self-Containment

Non-negotiable: this project is self-contained. The knowledge it depends on is held in-repo. An
external reference is allowed only as a public link or citation for further reading — never as a
load-bearing dependency on a resource outside the repository, and in particular never on an
external, local, personalized, or mutating repository, path, or tool. If an external document, repo,
or personal path is required to understand, build, or operate this project, copy its essential
knowledge into the repository (a doc, an ADR, or an inline comment) so the repo stays complete on
its own.

## Decisions

Non-negotiable: record every significant, hard-to-reverse decision as an ADR under `docs/decisions/`,
one decision per file, using the MADR-minimal `template.md`, so the rationale lives with the code.
Accepted ADRs are not deleted; a changed decision gets a new superseding ADR.

## Working Conventions

- Keep changes scoped and reversible; prefer editing existing files over adding new ones.
- Documentation and rationale live beside the code they describe.
- Directory structure is owned by the filesystem, not by prose. A `README.md` (or `AGENTS.md`)
  explains a directory's purpose — its domains, concepts, and rules — and never maintains a
  hand-copied file tree, which drifts the moment a file is added or renamed. When a listing aids
  discovery, give each entry a purpose, not a bare path the filesystem already shows. An
  auto-generated table of contents is the exception, since the generator keeps it in sync.
- Run the project's own lint and test tasks before proposing changes.
