# Review Report Template

The report must be easy for an LLM agent (Claude Code) to parse, extract findings from, and act on
programmatically. Use consistent Markdown headings, lists, and labels so the report stays
human-readable without losing structure.

Read `severity-levels.md` for severity definitions before writing.

---

## Output Format

Produce the report as a single block using the structure below. Do not deviate from the section
names or finding field labels. The consuming agent relies on consistent structure to extract and
prioritize work.

```md
## Verdict

**Status:** APPROVED|APPROVED_WITH_CONDITIONS|CHANGES_REQUIRED|REJECTED

Short summary: what was reviewed, overall assessment, most important findings. Stats: X findings (N
critical, N high, N medium, N low, N info)

## Plan Assessment

Brief assessment of the plan's approach, assumptions, and feasibility. If the plan is sound, one
sentence confirming that is enough. If the plan has fundamental issues, detail them here before
findings. Omit this section entirely if the plan itself has no issues.

## Findings

### F-001: Short description

**Severity:** CRITICAL|HIGH|MEDIUM|LOW|INFO **Category:**
correctness|security|performance|reliability|maintainability|compatibility **Location:**
`file path, line number, function name, or config key`

**Issue:** Clear description of what is wrong or concerning.

**Evidence:** What was found during research. Include [source URLs](https://example.com).

**Recommendation:** Exact fix or approach. Specific enough to act on without further research.

### F-002: Short description

**Severity:** ... **Category:** ... **Location:** `...`

**Issue:** ...

**Evidence:** ...

**Recommendation:** ...

Repeat for each finding. Order by severity: CRITICAL first, then HIGH, MEDIUM, LOW, INFO.

## Verification Checklist

| Status                                                                 | Claim                                                       | Notes                        |
| ---------------------------------------------------------------------- | ----------------------------------------------------------- | ---------------------------- |
| verified \| incorrect \| outdated \| unverified \| needs_clarification | The verifiable claim or dependency from the implementation. | Brief note, URL if relevant. |
| ...                                                                    | ...                                                         | ...                          |

## Tests

### Executed

Description of tests run and their results. Omit this subsection if no tests were executed.

### Recommended

1. **Target:** What to test (function, endpoint, flow). **Rationale:** Why this test matters and
   which finding it would catch.
2. **Target:** ... **Rationale:** ...

## Open Questions

1. **Q-001:** The question, with context on why it matters for correctness or safety.
2. **Q-002:** ...

Omit this section entirely if there are no genuine unknowns.

## Positive Notes

- What was done well and why it matters.
- Another strength to preserve.

Omit this section entirely if nothing notable was done well.

## References

- [Official source or documentation](https://example.com) - used for F-001, F-003
- [Another source](https://example.com) - used for F-002
```

---

## Verdict Criteria

- **APPROVED**: No critical or high findings. Medium/low findings are minor.
- **APPROVED_WITH_CONDITIONS**: No critical findings. Has high findings that are straightforward to
  fix. List conditions explicitly in the verdict body.
- **CHANGES_REQUIRED**: Has critical findings, or multiple high findings that compound into
  significant risk.
- **REJECTED**: Fundamental issues with the approach. The plan itself needs to be reconsidered.

## Writing Rules

- Every finding must be self-contained: the consuming agent should understand the issue from that
  single finding without reading the rest of the report.
- Use code blocks when referencing code, config values, or commands.
- Keep `Issue` to 1-3 sentences. Put detail in `Evidence`.
- `Recommendation` must be actionable: if the fix is a one-liner, include it. If it requires
  architectural change, describe the approach concretely.
- `Location` must be as specific as possible - file:line is ideal.
- Never leave `Evidence` empty. If you could not find external evidence, explain your reasoning. If
  you verified via search, include the URL.
- Keep field labels exact: `Severity`, `Category`, `Location`, `Issue`, `Evidence`,
  `Recommendation`.
- Status values must use the exact strings shown (uppercase verdict statuses, uppercase severities,
  lowercase categories, underscore-separated checklist statuses).
