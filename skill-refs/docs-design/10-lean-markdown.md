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

One related check is worth adding once the rule holds: `MD046` set to `fenced`, paired with the project's own rule that every fence declares a language. A second, `MD043`, fixes a document's exact heading list; it carries enough mechanism to need its own section below.

The migration is mechanical. Convert each emphasized span to inline code, a heading, or plain prose, one commit per area, and leave the prose tighter than you found it — dropping the bold lead-in habit usually shortens the sentence that carried it.

## Gating a fixed heading shape

Some documents are not free-form prose: their heading list is the contract. A slice entry document, a status surface, a decision record, and every template a project ships are all read by tools and sessions that assume the headings are where the shape says they are. `MD043 required-headings` is the check that holds that shape, and this section owns how it is wired. Which documents have a fixed shape is owned elsewhere: [07 — Plan and Slices](./07-plan-and-slices.md) for the plan zone, [02 — Lean ADRs](./02-lean-adrs.md) for decision records.

Four facts about the rule decide the wiring, and none of them is visible from the rule's name.

`MD043` is inert until it is given a `headings` array. A project config that enables the rule — including one that enables it implicitly through `default: true` — still checks nothing, because the rule has no list to compare against. A repository can carry the rule switched on for years and never fail a build.

The array cannot be set once for the repository. Every fixed-shape document has a different heading list, so a single repo-wide array would gate one document's shape and reject every other markdown file in the tree. Its configuration is per shape, not per project.

There is no per-glob rule configuration. markdownlint scopes configuration by directory and by nothing else: a `.markdownlint-cli2.*` or `.markdownlint.*` file applies to the directory it sits in and every subdirectory below it, merging with the versions above it. There is no `overrides` key and no way to attach a rule to a glob. A directory config therefore cannot separate a slice entry document from the `tasks.md` beside it, or a status surface from the charter in the same folder, so it cannot express a shape that is narrower than a subtree.

`--config <file>` loads any configuration file as the base for a run, and the directory config the tool discovers is merged over that base. This is the one seam that takes a filter, because the file set for the run is chosen outside the configuration.

So the array lives in one shape config, and the hook that runs the linter chooses which files it applies to. One file per shape, named so the tool accepts it — the name MUST end with a supported configuration name, so `slice-readme.markdownlint-cli2.jsonc` works and `slice-readme.jsonc` does not:

```jsonc
// .markdownlint/slice-readme.markdownlint-cli2.jsonc
// Heading shape for a slice entry document. The hook that names this file owns
// which documents it applies to.
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

The filter is one hook entry per shape. In `pre-commit` the entry reuses the linter's own hook and adds a file pattern and the config path, so a project keeps whatever language and dependency settings that hook already needed:

```yaml
- id: markdownlint-cli2
  alias: md-slice-readme
  name: markdownlint (slice entry heading shape)
  files: '^docs/plan/slices/[^/]+/README\.md$'
  args: ['--config', '.markdownlint/slice-readme.markdownlint-cli2.jsonc']
```

A shape config is an overlay, not a replacement. Every other rule still comes from the project config the tool discovers, so the shape config carries `MD043` and nothing else.

The project config MUST NOT mention `MD043` at all — not even to switch it off. It is discovered for the working directory and merged over the `--config` base, so an explicit `"MD043": false` silently undoes every shape config while the hooks keep reporting success. Omitting the rule is what a project wants anyway, because the rule is inert without an array: no ambient heading policy, an exact contract where a contract exists.

Both of this wiring's failure modes are silent — a project config that names `MD043`, and a shape config no hook entry reads — so a checklist item is the weakest place to hold them. A project that already runs its own repository-invariant tests SHOULD gate them there instead: assert that no discovered project config names `MD043` outside a comment, that every shape config supplies a `headings` array, and that every shape config is named by a hook entry. Three assertions over files that are already in the tree, and they fail loudly where the linter cannot.

The array is a complete ordered list. An extra heading, a missing heading, and a reordering all fail, and the failure names the heading it did not expect:

```text
docs/plan/milestones.md:26 error MD043/required-headings Required heading structure
  [Expected: [None]; Actual: ## bogus heading]
```

Where one heading's text varies per instance — a slice entry document whose H1 carries that slice's id and title — use `*`, which matches exactly one heading of any level and any text. `+` matches one or more. A slice shape therefore opens with `*` and fixes everything after it, which is also what lets one shape config cover a record and the template it was copied from.

Gate the documents whose shape is a contract, and nothing else. A wiki page, a guide, and a README are supposed to grow a heading when they have something new to say; gating them converts every honest addition into a lint failure and teaches the project to delete the rule rather than keep the shape.

### Keeping configuration out of the document

markdownlint also accepts a `markdownlint-configure-file` comment inside a document, and putting the array there is the obvious first idea: the shape then travels with the file, and a template carries its own gate wherever it is copied. Prefer the shape config anyway. The comment has to be repeated verbatim in every document of that shape, which is the duplication the rule's per-shape configuration was already forcing, and each copy is a place the array can drift without anything noticing. One array in one file, applied by a filter, is the same guarantee with one owner.

Two hazards follow from the inline form, and both are reasons a project is better off without it. The inline parser reads raw bytes: it does not know what a fenced code block or a code span is, so a comment shown as an example applies to the document showing it, and that document then fails against the heading list of whatever it was describing. The only escape is a file-level `markdownlint-disable-file MD043` comment in the document that quotes it — which this chapter does not need, precisely because it writes no such comment. And when one document carries two configure comments, the last one parsed wins, so a real gate at the top is silently replaced by an illustration further down. A project that keeps its arrays in shape configs never meets either.

## Anti-patterns

- Bolding every list item's first phrase, so the list reads as a wall of labels.
- Using bold where inline code belongs, which loses the signal that a token is a literal.
- Using lowercase "must" for a binding requirement in a normative document.
- Adding an emphasis budget instead of a ban, then negotiating it on every review.
- Configuring a formatter and assuming the rule is now enforced.
- Switching `MD043` on in the project config and assuming a shape is now gated, when the rule has no `headings` array to check against and passes everything.
- Copying one shape's heading array into every document that has that shape, so a new section means editing every copy and a stale copy gates a shape the project no longer has.
- Leaving `"MD043": false` in the project config, which merges over the shape config and switches off every gate while the hooks keep reporting success.
- Adding a shape config that no hook names, so the array is decoration.
- Fixing a heading list on a document that is supposed to grow headings, so the gate is deleted rather than maintained.
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
- Configuration file discovery, per-directory scoping, and `--config`: <https://github.com/DavidAnson/markdownlint-cli2#configuration>
- dprint markdown plugin configuration: <https://dprint.dev/plugins/markdown/config/>
