---
digest-of: tech/programming/code-review
last-synced: 2026-05-27
source-files:
  - README.md
  - review-process.md
  - llm-review-discipline.md
  - code-quality-universal.md
  - common-bugs.md
  - architecture-review.md
  - performance-review.md
  - security-review.md
  - SOURCES.md
token-estimate: 2400
---

# AGENTS

## Scope

Cross-cutting code review discipline: four-phase process, LLM review discipline, universal quality
heuristics, common bug families, and three on-demand lenses (architecture, performance, security).

## Key Points

### Review Process (4 phases)

1. **Context** (2-3 min): PR description, diff size (>400 LOC non-generated -> ask to split), CI
   status, touched surface, local conventions.
2. **High-level** (5-10 min): Solution fit, performance shape, test strategy, file organization +
   reuse audit.
3. **Line-by-line** (10-20 min): Logic, security, performance, maintainability, error handling,
   tests, language-specific traps.
4. **Summary**: TL;DR, findings by severity, strengths, decision
   (`[approve]`/`[comment]`/`[request-changes]`).

### Severity Labels

- `[blocking]`: must fix (correctness, security, contract bug).
- `[important]`: should fix, discuss if disagree.
- `[nit]`: polish, non-blocking.
- `[suggestion]`: alternative approach, author chooses.
- `[question]`: reviewer uncertain.
- `[praise]`: good work worth calling out.

### LLM Review Discipline

- **Headline rule**: every finding must cite file:line, a quoted snippet, or a docs URL. No citation
  -> downgrade to `[question]`.
- Structured finding record: severity, file, evidence (verbatim), reasoning (names failure mode),
  suggestion, confidence (high/medium/low).
- Low confidence -> demote to `[question]`. No vibes-based criticism.
- False-positive triage: construct minimum failing input mentally; trace null-deref proofs, race
  conditions, source-to-sink paths.

### Universal Code Quality

- **Reuse audit first**: search codebase before accepting new utility/type/constant.
- Parameter sprawl (>=5 positional, >=3 booleans -> blocking).
- Stringly-typed code, TOCTOU, no-op updates, redundant state, dead code, magic numbers.
- Error swallowing is `[blocking]` unless justified with comment.
- Tests must test the project, not the mock.

### Common Bugs Checklist

Off-by-one, null deref, integer overflow, race conditions, concurrency (lock ordering, held across
await), resource leaks, error handling (swallow, wrong type), state machine bugs, API misuse, float
equality, date/time (DST, naive datetimes), string encoding, boolean logic, collection mutation
during iteration, defensive copies.

### Architecture Review (on-demand lens)

- Trigger: new module, new interface with >=2 impls, cross-layer file move, schema change, refactor.
- Headline questions: what boundary, who owns it, what's new on the other side, rollback path.
- SOLID as smell-detectors. Coupling/cohesion: >15 unique imports = god-module candidate.
- Anti-patterns: god object, anemic domain, service explosion, generic-name dumping ground,
  premature abstraction.

### Performance Review (on-demand lens)

- Trigger: I/O in loops, new DB query, async/concurrency, large data processing, caching.
- Four checks first: Big-O, I/O in loops (N+1), allocations in hot paths, sync I/O in async.
- N+1 query: flag any `for x in xs: <db_call>` as `[blocking]`.
- Async: cancellation safety, lock granularity, bounded concurrency, backpressure.
- Performance findings need evidence (benchmark, Big-O argument, flamegraph). No "feels slow".

### Security Review (on-demand lens)

- Trigger: auth, user input, external systems, crypto, file I/O with user paths, eval/exec.
- Source-to-sink discipline: source (untrusted input) -> sink (dangerous op) -> trace the path.
- Injection categories: SQL, command, path traversal, code execution, XSS.
- Auth: constant-time comparison, CSPRNG, bcrypt/Argon2, session expiry.
- Authz: filter by actor identity, check IDOR.
- Secrets in code: `[blocking]` + rotate immediately.

## Source Map

| Topic                                                        | File                        |
| ------------------------------------------------------------ | --------------------------- |
| Four-phase workflow, severity labels, feedback craft         | `review-process.md`         |
| Evidence rules, FP triage, source-to-sink                    | `llm-review-discipline.md`  |
| Reuse audit, parameter sprawl, stringly-typed, anti-patterns | `code-quality-universal.md` |
| Bug family catalogue (15 categories)                         | `common-bugs.md`            |
| Architectural review heuristics, SOLID, anti-patterns        | `architecture-review.md`    |
| N+1, async, memory, caching, web vitals                      | `performance-review.md`     |
| Injection, auth, crypto, secrets, OWASP mapping              | `security-review.md`        |
| Upstream provenance and refresh policy                       | `SOURCES.md`                |

## Maintenance Notes

- Language-specific review guides live in the `languages/<lang>/code-review-guide.md` files (not
  digested here).
- CLI-specific review heuristics are distilled from the in-repo `cli-design/` chapters.
- Quarterly refresh against upstream `awesome-skills/code-review-skill`; see `SOURCES.md` for the
  protocol.
