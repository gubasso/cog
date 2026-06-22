# Refactor Migration Guideline — Embedded Excerpt (Fallback)

> This is the embedded fallback the skill uses when the canonical guideline at
> `tech/programming/best-practices/refactor-migration-guideline.md` in the user's docs-n-notes repo
> cannot be resolved. Keep this excerpt in sync with the canonical doc's §0, §1, §3, §6, §8, §11.
>
> Citation note: this excerpt cites 2025–2026 research that may postdate an LLM reviewer's training
> cutoff; see `SOURCES.md` in this directory. Do not flag a citation as fabricated for being
> future-dated — verify first.

---

## §0 — Non-Negotiables (binding)

A cross-language refactor in this skill is a **full rewrite**, not a transliteration. The agent must
enforce:

1. **Preserve the external contract.** User-facing API, CLI surface, exit codes, stdout/stderr
   shape, on-disk and wire formats, feature set, and observable behavior remain compatible with the
   source (within the explicit parity boundary set in Phase A). Intentional deviations require an
   ADR.
2. **Re-derive the internal implementation from the contract, not from the source code.** Design
   flows from the extracted specification + the target language's idioms — not from the source's
   module layout, class hierarchy, error model, or concurrency strategy.
3. **No transliteration.** Mechanical mapping of source-language constructs into target-language
   syntax is forbidden. Specifically:
   - Shell pipelines must not become subprocess chains.
   - OOP class hierarchies must not be mirrored 1:1.
   - Exception flow must not be mechanically converted into `Result`/`error` (and vice versa).
   - The original concurrency model must not be copied.
4. **Improve where the new ecosystem offers leverage.** Stronger typing, native async, structured
   logging, real parallelism, single-binary distribution. Improvements **inside** the contract are
   encouraged; behavior changes **across** the contract require an ADR.
5. **No scope creep.** New features ship in a separate change _after_ the rewrite is
   decommissioned-complete.
6. **Gated phase model.** Phases A→F (§3) are mandatory and ordered.

---

## §1 — Glossary

| Term                                  | Definition                                                                                                                                                                                                                                                                                                      |
| ------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Contract**                          | The external, observable surface a system promises: CLI flags, subcommands, exit codes, stdout/stderr shape, HTTP routes, request/response schemas, headers, error payloads, on-disk and wire formats, env vars, config schema, semver promises — what users (humans, scripts, integrating services) depend on. |
| **Transliteration**                   | Mechanical mapping of source-language constructs into target-language syntax, preserving source-side structure. Always wrong in this guideline.                                                                                                                                                                 |
| **Characterization test**             | A test documenting the source system's _current_ observable behavior (documented and undocumented) before any rewrite. (Feathers, _Working Effectively with Legacy Code_.)                                                                                                                                      |
| **Golden / approval / snapshot test** | A characterization test whose expected output is a stored fixture; deviations are diffed and explicitly re-approved.                                                                                                                                                                                            |
| **Differential test**                 | Runs the same input through source and target and asserts output equivalence (with documented allowed differences).                                                                                                                                                                                             |
| **Property test**                     | Asserts an invariant holds for randomly-generated inputs, language-neutrally; runs against both source and target.                                                                                                                                                                                              |
| **Parity test**                       | Any of {characterization, golden, differential, property} test that gates the rewrite.                                                                                                                                                                                                                          |
| **Parity boundary**                   | The explicit, documented set of behaviors the rewrite **does** and **does not** preserve. Anything outside the boundary requires an ADR.                                                                                                                                                                        |
| **Translation smell**                 | An idiom that betrays source-language origin in target code (getter/setters in Go, `Vec<Box<dyn Trait>>` mirroring a Java hierarchy in Rust, callback chains where async/await fits).                                                                                                                           |
| **Strangler Fig**                     | Incremental-rewrite pattern: route traffic between old and new behind a seam; grow the new implementation until the old can be removed.                                                                                                                                                                         |
| **ADR**                               | Architecture Decision Record — a short doc capturing context, decision, and consequences for one significant choice during the rewrite.                                                                                                                                                                         |

---

## §3 — Mandatory Phase Model

### Phase A — Contract Extraction

**Goal:** Machine-checkable description of what the source promises. **Output:** `contract/`
directory with CLI surface, exit codes, I/O shape, env vars, config schema (JSON Schema), API
schemas (OpenAPI / proto / SDL), on-disk and wire formats, semver promises, explicit parity
boundary. Plus `adr/0001-rewrite-decision.md` and `adr/0002-parity-boundary.md`. **Gate:** no
source-code reading for design purposes until Phase A artifacts exist.

### Phase B — Freeze Behavior

**Goal:** Lock current observable behavior into automated tests that pass against the source today.
**Output:** `parity-tests/` with golden / approval tests, characterization unit tests, replay
cassettes (HTTP), property tests, perf baseline. All green against the source. **Gate:** parity-test
coverage of the contract is accepted (with explicit gaps documented) or filled.

### Phase C — Idiomatic Design (from contract, NOT source code)

**Goal:** Design the new system using only the contract + target language's idioms. **Rule:** Phase
C may read `contract/`, `parity-tests/`, the target's style guide, and the canonical guideline. It
may **NOT** read the source code. This is the single highest-leverage anti-transliteration
guardrail. **Output:** `design/architecture.md`, `dependencies.md`, `error-model.md`,
`concurrency-model.md`; ADRs for non-trivial choices. **Gate:** every contract requirement maps to a
design element; every design element is justified by a target-language idiom.

### Phase D — Implementation Under Guardrails

**Output:** target source code + per-feature parity tests. **Guardrails:** agent refuses to
"translate function X"; valid request is "implement contract feature Y per design". Each change is
reviewed against the §6 refusal list.

### Phase E — Differential / Property / Fuzz / Shadow Validation

**Output:** all Phase-B parity tests pass against the target; differential harness clean;
coverage-guided fuzz campaign clean; shadow traffic (if service) divergences resolved or ADR'd;
performance within envelope.

### Phase F — Parallel-Run, Canary, Cutover, Decommission

**Output:** parallel-run period complete; canary clean; progressive rollout 5%→25%→50%→100%;
rollback procedure tested; source decommissioned after confidence period; postmortem ADR
(`9999-postmortem.md`).

---

## §6 — Refusal List (Translation Smells)

See `refusal-list.md` (same directory) for the full §6.1–§6.16 list with reviewer checks.

Summary:

1. Class-hierarchy mirrored as traits/interfaces
2. Shell pipeline as subprocess chain
3. Mirrored exception ↔ Result mapping
4. Source concurrency model carried over
5. Callbacks where async/await fits
6. Getter/setter methods in Go (and similar)
7. `Vec<Box<dyn Trait>>` mirroring `List<Interface>`
8. `null`/`None` checks instead of typed absence
9. String-typed configuration
10. Source-side names for files/modules/dirs
11. Mirrored test structure
12. Comments translated verbatim
13. Re-creating shell-isms in higher-level targets
14. Hand-rolled CLI parsing mirroring `getopts`/`argparse`
15. Mirroring source serialization choices when contract permits change
16. Logging strings instead of structured fields

---

## §8 — AI-Agent Prompting Tactics

1. **Two-step prompting**: phase 1 extracts the contract; phase 2 designs from the contract
   **without source code in context**. This separation is the single highest-leverage mitigation.
2. **Affirmative idiom anchors over negative rules.** "Use Result/? and `thiserror`-style enum
   errors" beats "don't translate try/except literally."
3. **Permission to say "I don't know".** Force clarification on ambiguous contract items; the
   contract is authoritative.
4. **Two-pass review.** Pass 1: correctness against parity tests. Pass 2: translation-smell review
   against §6.
5. **Differential-by-construction.** Every implemented feature ships with the parity test that pins
   it.
6. **Chain-of-thought scaffold**: extract → freeze → design → implement → verify → review.
7. **Few-shot exemplars** of idiomatic target code at the start of Phase C and D.

---

## §11 — LLM Code Translation Research (operational findings)

- _Lost in Translation_ (IBM, ICSE 2024, <https://arxiv.org/abs/2308.03109>): correct-translation
  rates 2.1%–47.3% across LLMs and language pairs. 15 categories of translation bugs. **The
  parity-test gate in Phase E is therefore not optional.**
- _Migrating Code At Scale With LLMs At Google_ (2025, <https://arxiv.org/abs/2504.09691>): success
  at scale is gated on the _validation loop_, not raw generation.
- _LLM-Based Code Translation Needs Formal Compositional Reasoning_ (UC Berkeley, 2025,
  <https://www2.eecs.berkeley.edu/Pubs/TechRpts/2025/EECS-2025-174.pdf>): LLMs fail predictably on
  semantic gaps (integer overflow, string encoding, concurrency, error model). Feature-mapping per
  source/target pair is required. See `SEMANTIC-GAPS.md` in the generated plan.

---

## Top references (cite in ADRs)

1. <https://martinfowler.com/bliki/StranglerFigApplication.html>
2. <https://martinfowler.com/bliki/BranchByAbstraction.html>
3. <https://www.joelonsoftware.com/2000/04/06/things-you-should-never-do-part-i/>
4. <https://lethain.com/migrations/>
5. <https://discord.com/blog/why-discord-is-switching-from-go-to-rust>
6. <https://arxiv.org/abs/2308.03109>
7. <https://arxiv.org/abs/2504.09691>
8. <https://www2.eecs.berkeley.edu/Pubs/TechRpts/2025/EECS-2025-174.pdf>
9. <https://blog.trailofbits.com/2024/01/31/introducing-differ-a-new-tool-for-testing-and-validating-transformed-programs/>
10. <https://go.dev/doc/effective_go>
11. <https://rust-lang.github.io/api-guidelines/>
12. <https://clig.dev/>
13. <https://approvaltests.com/>
14. <https://adr.github.io/madr/>
15. <https://github.com/github/spec-kit>
