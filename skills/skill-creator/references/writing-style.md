# Writing Style

> Skill prose is read by a model on every invocation. Ambiguity costs a wrong action, and length costs tokens. Write in the plain, controlled style below.

This profile follows Simplified Technical English in spirit. It does not claim ASD-STE100 compliance, which requires the official dictionary and qualified review.

## Classify the passage first

Every passage is procedural or descriptive. Do not mix the two in one section.

**Procedural** text tells the agent what to do.

- Imperative mood.
- Maximum 20 words per sentence.
- One instruction per sentence.

**Descriptive** text explains a thing.

- Simple tenses.
- Maximum 25 words per sentence.
- One topic per paragraph, maximum six sentences.

## Verbs

Use only these forms: infinitive, imperative, simple present, simple past, simple future, and past participle as an adjective.

- No present perfect. Write "the run completed", not "the run has completed".
- No `-ing` verb forms carrying an action. Start a new sentence instead.
- Active voice. Use passive voice only when the actor is unknown or irrelevant.

Use these modal verbs only: `can`, `will`, `must`.

Do not use `should`, `would`, `may`, `might`, or `could`. For `should`, write `must` when the rule is required, and delete the sentence when it is optional. An agent reads `should` as optional and skips it.

## Sentences

- Keep complete grammar. Keep articles. Keep the word "that".
- No contractions.
- Put a condition before the instruction it controls: "If the file is absent, create it."
- No semicolons. Write two sentences.
- No em-dashes. Name the relation with "because", "but", or "for example", or write two sentences.
- Use a vertical list for more than two items or steps.

## Words

- One word for one meaning, across the whole document. Pick one of check, verify, and confirm, then use it everywhere.
- Keep noun chains to three words. Break longer ones with a preposition: "the timeout value for the connection pool".
- Use a verb for an action, not a noun phrase. Write "validate the input", not "perform input validation".
- Delete words that carry no fact: simply, seamlessly, robust, powerful, comprehensive, leverage, in order to.
- Use the common word: "use", not "utilize". "before", not "prior to". "if", not "in the event that".
- American spelling.

## Warnings

State the command or condition first, then the risk.

```markdown
Do not run this against production. The command deletes rows.
```

A warning that opens with the risk buries the instruction.

## Protected text

These are never rewritten to fit the rules above, and each counts as one word toward a sentence limit:

- Code blocks and inline code.
- File paths, command names, and flags.
- Identifiers and literals.
- Quoted error messages.
- URLs.
- Product names.
- Text a user supplied, when the skill must carry it verbatim.

## Exceptions

- A normative specification can use the uppercase keywords MUST, MUST NOT, REQUIRED, SHALL, SHOULD, MAY as defined by BCP 14. That vocabulary overrides the modal rule above, and only inside a specification.
- A safety prohibition can use direct negative language, because the negative is the instruction.

## Before you finish

Scan the draft for each of these:

- Contractions.
- "has been" and "have been".
- "should", "would", "may", "might", "could".
- ", making" and other `-ing` clauses carrying an action.
- Semicolons and em-dashes.
- The deleted-word list above.

Then count the words in your three longest sentences. Split every sentence over the limit for its class.
