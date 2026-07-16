# AGENTS.md digest template

Copy this file into a content area as its `AGENTS.md`. A digest is a **map** of the area — loaded
first by an agent before it reads the underlying files — and never the source of truth. The content
files own the knowledge; this digest summarizes them. Regenerate it whenever a listed source file
changes or a new file is added; when the digest and a source disagree, the source wins.

Keep the frontmatter accurate: `digest-of` is the area path, `last-synced` is the date you
regenerated it, `source-files` lists the files it summarizes, and `token-estimate` is a rough size.

```markdown
---
digest-of: <path/to/this/area>
last-synced: <YYYY-MM-DD>
source-files:
  - <file-a.md>
  - <file-b.md>
token-estimate: <approx tokens>
---

# AGENTS

## Scope

<One or two sentences: what knowledge this area holds.>

## Key points

- <Load-bearing fact from a source file.>
- <Another fact, one bullet per idea.>

## Source map

| Topic     | File         |
| --------- | ------------ |
| <topic-a> | `<file-a.md>` |
| <topic-b> | `<file-b.md>` |

## Maintenance notes

- Regenerate when any listed source file changes or a new file is added.
- Keep this digest derived from the sources; do not introduce new rules here.
- Load this digest first, then read the source file that owns the current change.
```
