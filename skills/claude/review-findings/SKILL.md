---
name: review-findings
description: >
  Process and address code review findings from implementation reviews.
  Use when the user provides a review report, findings list, or feedback from a code review
  (self-review, peer review, or LLM-assisted review) and wants each finding triaged, validated,
  and addressed. Triggers: "review findings", "address findings", "fix review", "review report",
  "handle feedback", "address review points", "review comments", or when the user pastes a
  numbered/bulleted list of code review observations after an implementation task.
model: opus
effort: low
---

# Review Findings Processor

Process a list of code review findings, triage each one, and either address it or justify skipping
it.

## Input Expectations

The user provides:

1. **Review findings** -- a list of observations, issues, suggestions, or questions from a code
   review.
2. **Task context** (may already be in conversation) -- the original goal/task that was implemented.

If the task context is unclear, ask the user to briefly describe the original implementation goal
before proceeding.

## Workflow

For each finding in the list, execute these steps sequentially:

### Step 1: Classify the Finding

Determine the finding type:

- **Issue** -- a bug, incorrect usage, missing handling, style violation, etc.
- **Suggestion** -- an improvement idea, refactor proposal, optimization.
- **Question** -- a clarification request or knowledge gap from the reviewer.

### Step 2: Relevance Check

Evaluate:

1. **Does it make sense?** Is the observation technically correct and well-founded?
2. **Is it aligned with the task goal?** Or is it scope creep / tangential drift?

If the finding fails either check, skip to Step 5 (Justify Skip).

### Step 3: Verify Against Latest Docs (for Issues and Suggestions)

Before applying a fix, verify the finding against current documentation:

- Use web search to confirm the correct/latest API, method signature, config option, or best
  practice for the relevant tool, framework, or library mentioned in the finding.
- This prevents "fixing" something with outdated patterns or deprecated APIs.
- If the finding itself references an outdated API or pattern, note that in the output.

### Step 4: Address the Finding

Depending on classification:

- **Issue**: Fix/correct the code. Apply the change.
- **Suggestion**: Implement if it improves quality without scope creep. If borderline, ask the user.
- **Question**: Answer it if you have enough context. If you genuinely don't know or it requires
  user-specific knowledge, prompt the user for clarification.

### Step 5: Justify Skip (when applicable)

If a finding is skipped (irrelevant, wrong, out of scope, not worth the cost), provide a brief,
concrete justification. Don't be vague -- state _why_ it doesn't apply.

## Output Format

After processing all findings, produce a summary report. For each finding use this structure:

```text
### Finding N: <short title>
- **Type**: Issue | Suggestion | Question
- **Verdict**: Addressed | Skipped | Needs User Input
- **Reasoning**: <1-2 sentences on relevance and alignment>
- **Doc check**: <what was verified, source if relevant>
- **Action taken**: <what was changed, or why it was skipped, or the answer to the question>
```

At the end, include a brief **Summary** section with counts (addressed / skipped / needs input) and
any overarching observations.

## Guidelines

- Process findings in the order given. Don't reorder by severity unless the user asks.
- Be direct in justifications. "Not worth fixing" is acceptable if explained.
- When a finding is a question that you can answer confidently, just answer it.
- When a finding requires a code change, make the change and reference the file/line.
- If multiple findings overlap or conflict, note the dependency and handle them coherently.
- Do not gold-plate. Address what's asked, don't expand scope.
- If the findings list is very large (15+), give the user a quick overview of your triage plan
  before diving in, so they can reprioritize if needed.
