# Knowledge-base architecture

## The product is the knowledge

`<project>` is a knowledge base: a library of knowledge organized as directories and markdown files.
The **product** is that knowledge — the content tree itself. This is the same relationship a code
project has:

| Code project        | Knowledge base                          |
| ------------------- | --------------------------------------- |
| Code is the product | The markdown content is the product     |
| `docs/` = specs about the code | `docs/` = specs about the content |

So `docs/` here is not where the knowledge lives. The knowledge lives in the content directories at
the top of the repository. `docs/` holds the **specs about that product**: the definitions,
decisions, architecture, conventions, and patterns that govern how the knowledge base is structured
and maintained. When you want to record *how the knowledge base works*, write in `docs/`. When you
want to record *knowledge*, write in the content tree.

## Content structure

The content tree is owned by the filesystem. Organize it by subject, with directories that group
related knowledge and semantic filenames that expose a file's topic before it is opened. Avoid
`notes.md`, `misc.md`, and `final-v2.md`; prefer durable nouns.

Keep drafts out of the shipped content tree — normally under a gitignored `.draft/` — and promote a
draft by rewriting it into its durable home, then deleting the draft.

## The AGENTS.md digest standard

Every substantial content area carries an `AGENTS.md` **digest**: a concise map of that directory's
knowledge, loaded first by an agent (human or LLM) before it reads the underlying files. A digest is
a map, never the source of truth — the content files own the knowledge; the digest summarizes them.

A digest carries frontmatter that ties it to its sources and declares when it was last synced, so
staleness is visible:

```yaml
---
digest-of: <path/to/this/area>
last-synced: <YYYY-MM-DD>
source-files:
  - <file-a.md>
  - <file-b.md>
token-estimate: <approx tokens>
---
```

Regenerate a digest when any listed source file changes or a new file is added. When a digest and a
source file disagree, the source file wins and the digest is regenerated. Copy
[`../reference/agents-digest-template.md`](../reference/agents-digest-template.md) into a content
area as its `AGENTS.md` to start one.

This standard is a default feature of `<project>`: agents entering any area get an accurate,
up-to-date map before spending attention on the full content. See
[Documentation conventions](../reference/docs-conventions.md) for the placement and
single-source-of-truth rules that make the digests trustworthy.
