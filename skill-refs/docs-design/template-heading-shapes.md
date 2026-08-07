# Template — heading shapes

Drop-in wiring for `MD043 required-headings`. One configuration file per fixed shape, one hook entry per shape to choose the documents it applies to. The mechanism and the reasoning are in [10 — Lean Markdown](./10-lean-markdown.md#gating-a-fixed-heading-shape); this file is what to copy.

Copy the configuration files into `<project>/.markdownlint/` and the hook entries into the project's hook runner. Adjust the paths in `files` to the project's layout, and drop any shape the project does not have.

## The project config must not mention MD043

Before adding anything, check the project's own `.markdownlint-cli2.jsonc` or `.markdownlint.*` and remove `MD043` from it if present, including `"MD043": false`. That file is discovered for the working directory and merged over the `--config` base, so any value there silently overrides every shape below and the hooks keep reporting success. The rule is inert without a `headings` array, so leaving it out is the correct state.

## `.markdownlint/slice-readme.markdownlint-cli2.jsonc`

```jsonc
// Heading shape for a slice entry document. The `md-slice-readme` hook owns which
// documents this applies to. The leading `*` matches the varying H1.
{
  "config": {
    "MD043": {
      "headings": [
        "*",
        "## Goal",
        "## Appetite",
        "## Core",
        "## In scope",
        "## Out of scope",
        "## Governed by",
        "## Acceptance",
        "## Rabbit holes",
        "## Done when",
        "## Revisions"
      ]
    }
  }
}
```

## `.markdownlint/milestones.markdownlint-cli2.jsonc`

```jsonc
// Heading shape for the status surface. The H1 is fixed, so no `*` is needed. A
// project that has moved `## closed` out to `milestones-closed.md` drops that entry.
{
  "config": {
    "MD043": {
      "headings": ["# Milestones", "## in flight", "## closed"]
    }
  }
}
```

## `.markdownlint/adr.markdownlint-cli2.jsonc`

```jsonc
// Heading shape for a decision record. The leading `*` matches both the varying
// record title and the template's placeholder H1, so one shape covers both.
{
  "config": {
    "MD043": {
      "headings": [
        "*",
        "## Context and Problem Statement",
        "## Considered Options",
        "## Decision Outcome",
        "## Consequences",
        "## Status"
      ]
    }
  }
}
```

## Hook entries

For `pre-commit`, add one entry per shape alongside the project's existing markdownlint hook, reusing that hook's id so its language and dependency settings carry over. `alias` keeps each entry individually runnable, and `files` is the filter:

```yaml
- id: markdownlint-cli2
  alias: md-slice-readme
  name: markdownlint (slice entry heading shape)
  files: '^docs/plan/slices/[^/]+/README\.md$'
  args: ['--config', '.markdownlint/slice-readme.markdownlint-cli2.jsonc']

- id: markdownlint-cli2
  alias: md-milestones
  name: markdownlint (milestones heading shape)
  files: '^docs/plan/milestones\.md$'
  args: ['--config', '.markdownlint/milestones.markdownlint-cli2.jsonc']

- id: markdownlint-cli2
  alias: md-adr
  name: markdownlint (decision record heading shape)
  files: '^docs/decisions/(ADR-.*|template)\.md$'
  args: ['--config', '.markdownlint/adr.markdownlint-cli2.jsonc']
```

Any runner works the same way, because the only requirement is that something chooses the file set and passes `--config`. Under another runner the equivalent is one command per shape:

```bash
markdownlint-cli2 --config .markdownlint/slice-readme.markdownlint-cli2.jsonc "docs/plan/slices/*/README.md"
```

## Verify the gate is live

An array no hook reads is decoration, so prove each shape fails before trusting it. Add a heading the shape does not allow, run that shape's hook, and confirm the failure names the heading:

```text
docs/plan/slices/012-human-presentation/README.md:97 error MD043/required-headings
  Required heading structure [Expected: [None]; Actual: ## Status]
```

Then remove the heading. A shape that cannot be made to fail is not wired.
