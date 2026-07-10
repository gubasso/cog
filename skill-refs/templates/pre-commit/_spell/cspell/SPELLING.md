# Spelling in this knowledge base

Spell checking is `cspell`, run report-only by pre-commit on markdown files. It
flags unknown words; it never rewrites your prose. The default language is
English; Brazilian Portuguese is switched on per file.

## Where does a word belong? (three tiers, most-local last)

1. **Portuguese language words** — don't touch the word list. Put this at the top
   of the Portuguese file:

   ```markdown
   <!-- cspell:dictionaries pt-br -->
   ```

   The whole file is then checked against English **and** Brazilian Portuguese.
   (cspell has no per-file "locale" comment; `dictionaries` is the switch, and
   the dictionary's name is `pt-br`.)

2. **Project jargon / proper nouns used across files** — a tool name, product
   name, or initialism (Neovim, dprint, XDG). Add it, sorted, to
   `project-words.txt`. It is then correct everywhere.

3. **A correct word that appears in ONE file only** — keep it local; don't
   pollute the shared list:

   ```markdown
   <!-- cspell:words myOneOffTerm -->
   ```

   For a deliberate misspelling (e.g. inside a quotation) that must stay as-is,
   put `<!-- cspell:disable-next-line -->` above it, or wrap a block in
   `<!-- cspell:disable -->` … `<!-- cspell:enable -->`.

## Worked example (a bilingual note)

```markdown
<!-- cspell:dictionaries pt-br -->
<!-- cspell:words exobrain -->

# Configuração do Neovim no meu exobrain

Este documento descreve como configurei o **Neovim** com `dprint`.
```

Here `configuração`/`documento`/`descreve` pass via **pt-br**; `Neovim` and
`dprint` pass via **project-words.txt**; `exobrain` is file-local via
`cspell:words`.

## What is NOT checked

Fenced code blocks, inline `code`, URLs, and markdown link targets are skipped by
design — spelling is for prose, not for shell commands and identifiers.

## First run

```bash
pre-commit run cspell --all-files
```

Expect a batch of unknown words the first time. Triage each into tier 1, 2, or 3
above. Don't blanket-add real typos — fix those in the prose.
