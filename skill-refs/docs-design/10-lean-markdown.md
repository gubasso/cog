# 10 — Lean Markdown

<!-- markdownlint-disable-file MD043 -->

Markdown is the house format for project documentation and should stay that way. The rule this chapter adds is narrower: keep the constructs that carry structure, drop the inline emphasis that only carries decoration. The split matters more now that agents author most documentation, because agents over-format by default and the result is tiring to read and weaker to retrieve from.

## Problem

Two failures arrive together in agent-authored docs.

The first is emphasis inflation: a bold lead-in on every list item, a bold clause in every paragraph, italics for tone and for a term's first mention. Nothing is wrong, but the reader stops seeing emphasis as a signal because there is no unmarked text left to contrast against. Typography research is consistent here — dense emphasis reduces comprehension across the whole document, not only in the emphasized spans, and is worse for readers with cognitive disabilities. The common practitioner threshold is under five to ten percent of a page emphasized.

The second is emphasis standing in for structure: a bolded phrase as a section marker, a bolded noun as a field label, a bolded identifier to say "this is a name". Each has a real construct that already exists and that a parser can see, and using bold instead throws that structure away.

Neither failure is an argument against markdown. Prompt format changes measured task accuracy substantially for weaker models and less for stronger ones, with the stronger model favoring markdown over serialized formats, while tightening format restrictions measurably degrades reasoning. The conclusion is not to strip markdown down; it is to spend it on structure and stop spending it on decoration.

## The split

Structural markdown is kept and used deliberately:

- Headings. They carry the document's shape and are what retrieval keys on.
- Ordered and unordered lists, for genuinely parallel items or sequences.
- Tables, for comparisons and exact mappings.
- Fenced code blocks, always with a language; use `text` when no language applies.
- Inline code, for identifiers, paths, flags, commands, enum values, and status names.
- Links.
- Blockquotes, for actual quoted material only.

Decorative markdown is dropped:

- Bold and italics, everywhere, including in the drafts workspace.
- Bold lead-ins on list items. The list marker plus the opening noun phrase already carries it.
- Bold or italic text used as a pseudo-heading or a section marker.
- Emphasis on an identifier that inline code or a link already marks.
- Italics for scare quotes, tone, or a term's first mention.

The rule is zero, not "sparingly". A density budget invites a judgment call on every line and loses it slowly. Zero is checkable, and it is the only version an agent will apply consistently.

## Replacements

Emphasis was doing three jobs, and each has a better home.

Identifiers move to inline code. Write `Accepted`, `--dry-run`, `<project>/docs/decisions/`, not the bolded equivalents. This absorbs most decorative bold on its own.

Normativity moves to uppercase keywords: MUST, MUST NOT, REQUIRED, SHALL, SHALL NOT, SHOULD, SHOULD NOT, MAY. RFC 8174 defines these as normative only when capitalized, which means lowercase prose stays readable while binding statements remain greppable. Use them in normative documents — specifications, invariants, acceptance criteria — and not in narrative chapters, where they read as shouting.

Structure moves to headings. Anything tempting to bold as a mini-heading becomes an `###`. If that produces too many headings, the section was carrying more than one idea.

Do not justify this rule with token savings. Measured against real documentation corpora, emphasis markers account for roughly one to two percent of tokens; the dominant costs are restatement of facts another document already owns and long relative link paths repeated on every page. Fix those with the placement rules in [00 — Foundations](./00-foundations.md). This chapter is about signal, not volume. The one budget worth stating is file length for always-loaded instruction files, in [04 — Agent Context](./04-agent-context.md).

## Enforcement

No formatter or linter in the usual toolchain can enforce this rule, and it is worth knowing why before reaching for configuration.

A markdown formatter normalizes emphasis, it does not remove it. The dprint markdown plugin exposes `emphasisKind` and `strongKind`, and both only choose which character is used. There is no option that bans emphasis. markdownlint has no rule forbidding inline emphasis either: `MD036` fires only on a whole paragraph consisting of emphasized text and ending without punctuation, so a bolded lead-in followed by prose passes it, and `MD049` and `MD050` only pick the delimiter style.

So enforcement is a small project-local hook. Keep it fence-aware — strip fenced blocks and inline code spans before matching, or a `**/*.md` glob inside a fence will trip it — and run it before the formatter. Give it an escape hatch that costs a sentence in the diff rather than a habit, an `<!-- allow-emphasis: <reason> -->` comment on the preceding line, so a genuine exception is a recorded decision.

One related check is worth adding once the rule holds: `MD046` set to `fenced`, paired with the project's own rule that every fence declares a language. A second, `MD043`, pins a document's exact heading list; it carries enough mechanism to need its own section below.

The migration is mechanical. Convert each emphasized span to inline code, a heading, or plain prose, one commit per area, and leave the prose tighter than you found it — dropping the bold lead-in habit usually shortens the sentence that carried it.

## Pinning a fixed heading shape

Some documents are not free-form prose: their heading list is the contract. A slice entry document, a status surface, a decision record, and every template a project ships are all read by tools and sessions that assume the headings are where the shape says they are. `MD043 required-headings` is the check that holds that shape, and this section owns how it is wired. Which documents have a fixed shape is owned elsewhere: [07 — Plan and Slices](./07-plan-and-slices.md) for the plan zone, [02 — Lean ADRs](./02-lean-adrs.md) for decision records.

Three facts about the rule decide the wiring, and none of them is visible from the rule's name.

`MD043` is inert until it is given a `headings` array. A project config that enables the rule — including one that enables it implicitly through `default: true` — still checks nothing, because the rule has no list to compare against. A repository can carry the rule switched on for years and never fail a build.

The array cannot be set once for the repository. Every fixed-shape document has a different heading list, so a single repo-wide array would gate one document's shape and reject every other markdown file in the tree. This is the rule's defining constraint: its configuration is per document, not per project.

So the pin travels inside the document it governs, as a `markdownlint-configure-file` comment placed directly under the H1:

```markdown
# Milestones

<!-- markdownlint-configure-file { "MD043": { "headings": ["# Milestones","## in flight","## closed"] } } -->
```

That placement is what makes the shape survive being copied. A project that adopts a template inherits the gate in the same file, with no config file to port and no setup step to forget — the only thing it needs is a markdownlint hook that runs at all. An inline `markdownlint-configure-file` comment also overrides the project config, including an explicit `"MD043": false`, so a project MAY disable the rule repository-wide and still pin individual documents. Disabling it repository-wide and pinning per document is the recommended default, because it states the intent: no ambient heading policy, an exact contract where a contract exists.

The array is a complete ordered list. An extra heading, a missing heading, and a reordering all fail, and the failure names the heading it did not expect:

```text
docs/plan/milestones.md:26 error MD043/required-headings Required heading structure
  [Expected: [None]; Actual: ## bogus heading]
```

Where one heading's text varies per instance — a slice entry document whose H1 carries that slice's id and title — use `*`, which matches exactly one heading of any level and any text. `+` matches one or more. A slice pin therefore opens with `*` and fixes everything after it:

```json
{
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
```

Pin the documents whose shape is a contract, and nothing else. A wiki page, a guide, and a README are supposed to grow a heading when they have something new to say; pinning them converts every honest addition into a lint failure and teaches the project to delete the comment rather than keep the shape.

### Writing about the pin

The inline configuration parser reads the raw file. It does not know what a fenced code block is, and it does not know what an inline code span is, so a `markdownlint-configure-file` comment shown as an example is applied to the document showing it — a chapter that documents the mechanism, a template that ships the comment inside a fenced block, an ADR that quotes one. The document then fails against the heading list of whatever it was describing. No fence language, no indentation, and no code span prevents this; the only escape is to exempt the document that quotes the comment:

```markdown
<!-- markdownlint-disable-file MD043 -->
```

This chapter and the [plan-zone template](./template-plan-zone.md) both carry that line for exactly this reason. A template whose body is copied verbatim rather than quoted inside a fence — the [slice template](./template-slice.md) — needs no exemption, because its own headings are the shape it teaches, so the pin it ships is a real pin and the template gates itself.

For the same reason, do not write two `markdownlint-configure-file` comments in one document expecting the real one to win. The last one parsed takes effect, so a genuine pin at the top is silently replaced by an illustrative one further down.

- Bolding every list item's first phrase, so the list reads as a wall of labels.
- Using bold where inline code belongs, which loses the signal that a token is a literal.
- Using lowercase "must" for a binding requirement in a normative document.
- Adding an emphasis budget instead of a ban, then negotiating it on every review.
- Configuring a formatter and assuming the rule is now enforced.
- Switching `MD043` on in the project config and assuming a shape is now pinned, when the rule has no `headings` array to check against and passes everything.
- Pinning a heading list on a document that is supposed to grow headings, so the pin is deleted rather than maintained.
- Applying the rule to shipped docs but exempting the drafts workspace, so every promotion carries a cleanup step.
- Stripping structural markdown along with the decorative kind, which removes the headings and tables that retrieval and comprehension both depend on.

## Sources

- Prompt format and model performance: <https://arxiv.org/abs/2411.10541>
- Format restriction and reasoning: <https://arxiv.org/abs/2408.02442>
- Markdown awareness benchmark: <https://arxiv.org/abs/2501.15000>
- Normative keyword capitalization: <https://www.rfc-editor.org/rfc/rfc8174.txt>
- Emphasis and readability: <https://uit.stanford.edu/accessibility/learn-about/typography/italics-bold>
- markdownlint rule reference: <https://github.com/DavidAnson/markdownlint/blob/main/doc/Rules.md>
- `MD043` parameters and the `*` and `+` match tokens: <https://github.com/DavidAnson/markdownlint/blob/main/doc/md043.md>
- Inline configuration comments, including `markdownlint-configure-file`: <https://github.com/DavidAnson/markdownlint#configuration>
- dprint markdown plugin configuration: <https://dprint.dev/plugins/markdown/config/>
