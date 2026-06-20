# Severity Levels

Use these severity levels consistently across all findings in the review report. Each finding must
have exactly one severity. Use the decision criteria below to select it.

## CRITICAL

Immediate risk of data loss, security breach, service outage, or corruption. The implementation must
not be deployed or merged without addressing this. Examples:

- SQL injection vector in user-facing endpoint.
- Credentials hardcoded in source code.
- Race condition that can corrupt persistent data.
- Missing authentication on a privileged endpoint.
- Library version with a known actively-exploited CVE.

## HIGH

Significant correctness, security, or reliability issue that will cause problems in production but
may not be immediately catastrophic. Examples:

- Missing error handling on a critical path (crashes under predictable conditions).
- Incorrect API usage that works in tests but fails under real load or data.
- Deprecated API that will break on next dependency update.
- Missing input validation that could lead to unexpected behavior.
- Resource leak that degrades performance over time.

## MEDIUM

Issue that affects quality, maintainability, or has potential to cause problems under specific but
realistic conditions. Examples:

- Missing pagination on a query that will grow over time.
- Error messages that leak internal implementation details.
- Missing retry logic on a flaky external dependency.
- Inconsistent error handling patterns across the codebase.
- Missing timeouts on external HTTP calls.

## LOW

Minor issue, style concern, or improvement opportunity. Will not cause failures but should be
addressed for code health. Examples:

- Suboptimal algorithm where data scale does not warrant optimization.
- Missing log context that would help debugging.
- Inconsistent naming conventions.
- Missing doc comments on public interfaces.
- Redundant code that could be simplified.

## INFO

Not a problem. An observation, suggestion, alternative approach, or positive note about something
done well. Examples:

- "The retry strategy here is well-implemented with exponential backoff."
- "Consider extracting this into a shared utility if other services need it."
- "There is a newer API for this that simplifies the implementation."
- "The test coverage for this module is thorough."

## Decision Criteria

When choosing a severity level, ask these questions in order:

1. Can this cause data loss, a security breach, or a full outage? → CRITICAL
2. Will this cause failures in production under normal conditions? → HIGH
3. Could this cause failures under realistic edge cases or degrade over time? → MEDIUM
4. Is this a code quality issue with no runtime impact? → LOW
5. Is this a suggestion or positive observation? → INFO

When uncertain between two adjacent levels, choose the higher severity. It is better to over-report
than to under-report.
