# Review Process

The four-phase workflow every `review-code-deep` invocation follows. Severity vocabulary, feedback
craft, and decision criteria live here so SKILL.md stays thin.

## Phase 1 — Context (2–3 min)

Before reading code, establish intent.

1. PR title, description, linked issue. If missing, ask the author.
2. Diff size. >400 lines of non-generated code → ask to split before deep-reviewing.
3. CI status. Red tests are blocking; do not signal-off until they're green.
4. Touched surface. `git diff --stat` to see which packages/modules are involved.
5. Local conventions. CLAUDE.md, AGENTS.md, repo README at the touched dirs.

Output of this phase: a one-sentence summary of _what the change is supposed to do_, and a list of
languages + cross-cutting concerns to load references for.

## Phase 2 — High-level (5–10 min)

Architecture before lines. A good local change can still be a bad shape.

1. **Does the solution fit the problem?** Look for misplaced responsibility, premature abstraction,
   leaky boundaries. See [architecture-review.md](architecture-review.md) when the diff crosses
   module boundaries.
2. **Performance shape.** Algorithm complexity, N+1 queries, hot-path allocations. See
   [performance-review.md](performance-review.md) for the per-tier playbook.
3. **Test strategy.** Does the test suite exercise the new behavior at the right tier
   (unit/integration/contract)? Are there assertions on side effects or just on returns?
4. **File organization.** New files in the right places per the repo's convention? See
   [code-quality-universal.md](code-quality-universal.md) for the "reuse audit" — search for
   existing utilities before accepting new code.

## Phase 3 — Line-by-line (10–20 min)

For each modified file, scan for:

- **Logic & correctness** — off-by-one, null/undefined dereferences, race conditions, missing
  branches, default cases, integer overflow.
- **Security** — input validation, injection (SQL, command, path traversal), auth/authz, secrets in
  code, sensitive logging. See [security-review.md](security-review.md).
- **Performance** — repeated allocation in loops, sync I/O in async paths, missing indexes,
  unnecessary copying.
- **Maintainability** — clear names, single responsibility, dead code, magic numbers.
- **Error handling** — every fallible operation has a path, errors carry context, no silent
  swallows.
- **Tests** — covers the new branches, asserts on behavior not on mocks, deterministic.
- **Common bugs by language** — load `languages/<lang>.md` for the language-specific traps.

Use [llm-review-discipline.md](llm-review-discipline.md) to keep findings evidence-grounded and the
false-positive rate low.

## Phase 4 — Summary & decision (2–3 min)

1. **One-paragraph TL;DR** of the change.
2. **Findings list**, grouped by file, ordered by severity (descending).
3. **Strengths** (≥1 item if any are present — review is two-way).
4. **Decision**:

   - `[approve]` — ship it.
   - `[comment]` — minor suggestions, non-blocking.
   - `[request-changes]` — at least one `[blocking]` finding; must address before merge.

5. **Offer to pair** when the change is complex or the reviewer's confidence is low.

## Severity labels

Every finding carries exactly one of these. Use the verbatim tag so reports are tool-parseable.

| Tag            | Meaning                                                                                |
| -------------- | -------------------------------------------------------------------------------------- |
| `[blocking]`   | Must fix before merge. Correctness, security, or contract bug.                         |
| `[important]`  | Should fix. Discuss if you disagree, but default is "address it".                      |
| `[nit]`        | Polish or style. Non-blocking. Suppressed by `--severity blocking`/`important`.        |
| `[suggestion]` | "Have you considered X?" — alternative approach. Author chooses.                       |
| `[question]`   | Reviewer is uncertain; asks before stating. Downgrade-target for speculative findings. |
| `[praise]`     | Good work worth calling out. Use sparingly; not every PR has one.                      |

`--severity blocking` filters out everything below blocking. `--severity important` keeps blocking +
important.

## Feedback craft

### Question, not command

Reviewers ask; they don't dictate. The author chose the design once already; the reviewer is
inviting them to revisit.

```text
Bad:  "Extract this into a function."
Good: "This logic appears in 3 places — would extracting help, or is the inline form clearer
       in context?"

Bad:  "You need error handling here."
Good: "How should this behave if the API call fails? I don't see a path for that."
```

### Specific, not abstract

Every finding cites the exact file:line and the exact failure mode. "This is confusing" is useless;
"On `auth.rs:42`, `user_id` is shadowed inside the loop — the outer value is unused afterward" is
actionable.

### Educational when warranted

When you flag an anti-pattern the author may not recognize, link the canonical reference (language
guide, RFC, OWASP entry) so the next reviewer doesn't have to teach the same lesson. Don't lecture
in-line.

### Balanced

Calling out one strength per review keeps the relationship two-way and signals what to keep doing.
Skip when there's nothing genuine to praise — empty praise is worse than none.

## What to skip

Linters and formatters own:

- Code formatting (Prettier, Black, rustfmt, shfmt).
- Import organization.
- Lint violations the project enforces in CI.
- Simple typos in code identifiers (the compiler/type-checker catches these).

If a project has no linter for something you'd want to flag, raise it as a meta-issue ("can we
enforce X in CI?") rather than commenting on every PR.

## Time budget

The phase durations above are calibrated for a ~200-line diff. Scale linearly. If a single phase
blows past 2× its budget, the review is too big — ask to split or escalate.
