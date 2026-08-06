# 10 — Lean Markdown

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

Two related checks are worth adding once the rule holds: `MD046` set to `fenced`, paired with the project's own rule that every fence declares a language; and `MD043`, which pins a document's exact heading list, scoped to directories whose documents have a fixed shape such as templates and per-unit-of-work files.

The migration is mechanical. Convert each emphasized span to inline code, a heading, or plain prose, one commit per area, and leave the prose tighter than you found it — dropping the bold lead-in habit usually shortens the sentence that carried it.

## Anti-patterns

- Bolding every list item's first phrase, so the list reads as a wall of labels.
- Using bold where inline code belongs, which loses the signal that a token is a literal.
- Using lowercase "must" for a binding requirement in a normative document.
- Adding an emphasis budget instead of a ban, then negotiating it on every review.
- Configuring a formatter and assuming the rule is now enforced.
- Applying the rule to shipped docs but exempting the drafts workspace, so every promotion carries a cleanup step.
- Stripping structural markdown along with the decorative kind, which removes the headings and tables that retrieval and comprehension both depend on.

## Sources

- Prompt format and model performance: <https://arxiv.org/abs/2411.10541>
- Format restriction and reasoning: <https://arxiv.org/abs/2408.02442>
- Markdown awareness benchmark: <https://arxiv.org/abs/2501.15000>
- Normative keyword capitalization: <https://www.rfc-editor.org/rfc/rfc8174.txt>
- Emphasis and readability: <https://uit.stanford.edu/accessibility/learn-about/typography/italics-bold>
- markdownlint rule reference: <https://github.com/DavidAnson/markdownlint/blob/main/doc/Rules.md>
- dprint markdown plugin configuration: <https://dprint.dev/plugins/markdown/config/>
