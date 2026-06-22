# Cross-Language Refactor / Migration Guideline

> $refactor $migration $rewrite $cross-language $ai-agents $claude-code $codex $strangler-fig
> $characterization-tests $differential-testing $contract-preservation $idiomatic-code
> $llm-code-translation

A canonical, **language-agnostic** guideline for refactoring/rewriting a project from one technology
to another (Bash → Rust, Python → Go, Ruby → TypeScript, JS → Rust, Java → Kotlin, …). Intended to
be loaded as a prompt / skill injection by AI coding agents (Claude Code, Codex CLI, Cursor, Aider,
Cline, …) **every time** a cross-language refactor/rewrite is undertaken.

This document is the source of truth for "how we rewrite". It is _not_ a discussion of _when_ to
rewrite — assume the decision is made.

---

## 0. Non-Negotiables (read this section first)

A cross-language refactor in this guideline is a **full rewrite**, not a transliteration. The agent
must internalize and enforce these non-negotiable rules:

1. **Preserve the external contract.** The user-facing API, CLI surface, exit codes, stdout/stderr
   shape, on-disk and wire formats, feature set, and observable behavior must remain compatible with
   the source system (within the explicit parity boundary set in Phase A). Where parity is
   intentionally broken, document it as an ADR.
1. **Re-derive the internal implementation from the contract, not from the source code.** Design
   must flow from the extracted specification plus the target language's idioms — _not_ from the
   source's module layout, class hierarchy, error model, or concurrency strategy.
1. **No transliteration.** Mechanical mapping of source-language constructs into target-language
   syntax is forbidden. Specifically:
   - Shell pipelines must not become subprocess chains; redesign in the target's I/O primitives.
   - OOP class hierarchies must not be mirrored 1:1 into Go interfaces, Rust traits, or functional
     types.
   - Exception flow must not be mechanically converted into `Result`/`error` returns (and vice
     versa) — re-derive the error model from the contract.
   - The original concurrency model (threads vs. async vs. green threads vs. processes) must not be
     copied; choose what fits the target language and workload.
1. **Improve where the new ecosystem offers leverage.** Stronger typing, native async, structured
   logging, real parallelism, better packaging, single-binary distribution, faster I/O — use them.
   Improvements **inside** the contract are encouraged; behavioral changes **across** the contract
   require an explicit ADR.
1. **No scope creep.** The rewrite preserves features and adds nothing that did not exist in the
   source. New features ship in a separate change _after_ the rewrite is decommissioned-complete.
   See
   [§7 anti-patterns: second-system effect](#7-anti-patterns--failure-modes-named-in-the-literature).
1. **Gated phase model.** Phases A→F (see [§3](#3-mandatory-phase-model)) are mandatory and ordered.
   Skipping or reordering phases is a defect; agents must refuse to advance until the previous
   phase's artifacts exist.

> The dominant failure mode of LLM-driven rewrites is **transliteration smell** — code that is
> syntactically the target language but structurally the source language. The whole point of this
> guideline is to make that failure mode hard to commit.

---

## 1. Glossary

| Term                                            | Definition                                                                                                                                                                                                                                                                                                                            |
| ----------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Contract**                                    | The external, observable surface a system promises: CLI flags, subcommands, exit codes, stdout/stderr shape, HTTP routes, request/response schemas, headers, error payloads, on-disk formats, wire formats, env vars, config schema, semver promises. The contract is what users (humans, scripts, integrating services) _depend on_. |
| **Transliteration**                             | Mechanical mapping of source-language constructs into target-language syntax, preserving source-side structure. Always wrong in this guideline.                                                                                                                                                                                       |
| **Characterization test**                       | A test that documents the _current_ observable behavior of the source system before any rewrite. Captures both documented and undocumented behavior. (Feathers, _Working Effectively with Legacy Code_.)                                                                                                                              |
| **Golden test / approval test / snapshot test** | A characterization test where the expected output is a stored fixture; deviations are diffed and explicitly re-approved.                                                                                                                                                                                                              |
| **Differential test**                           | A test that runs the same input through the source and target implementations and asserts output equivalence (with documented allowed differences).                                                                                                                                                                                   |
| **Property test**                               | A test that asserts an invariant holds for randomly-generated inputs, language-neutrally. Runs against both source and target.                                                                                                                                                                                                        |
| **Parity test**                                 | Any of {characterization, golden, differential, property} test that gates the rewrite.                                                                                                                                                                                                                                                |
| **Parity boundary**                             | The explicit, documented set of behaviors the rewrite **does** and **does not** preserve. Anything outside the boundary requires an ADR.                                                                                                                                                                                              |
| **Translation smell**                           | An idiom that betrays source-language origin in target-language code (e.g., getter/setter methods in Go, `Vec<Box<dyn Trait>>` mirroring a Java class hierarchy in Rust, callback chains where async/await fits).                                                                                                                     |
| **Strangler Fig**                               | An incremental rewrite pattern: route traffic between old and new behind a seam; grow the new implementation until the old can be removed.                                                                                                                                                                                            |
| **ADR**                                         | Architecture Decision Record. A short doc capturing context, decision, and consequences for one significant choice during the rewrite.                                                                                                                                                                                                |

---

## 2. The Core Principle (one paragraph for prompt injection)

> A cross-language rewrite preserves the **external contract** (CLI surface, API, observable
> behavior, on-disk/wire formats, semver promises) and **re-derives the internal implementation** in
> the target language's idioms. The agent must (a) extract the contract from the source as
> machine-checkable artifacts, (b) freeze the source's current behavior in characterization tests,
> (c) design the new system from the contract — not from the source code — using the target
> language's official style guides and idiomatic ecosystem, (d) implement under anti-transliteration
> guardrails, (e) verify with golden/property/differential/fuzz/shadow tests against the frozen
> behavior, and (f) cut over via parallel-run with an explicit rollback. Transliteration is
> forbidden. Scope creep is forbidden.

---

## 3. Mandatory Phase Model

Six gated phases. Each phase has required artifacts. Agents must refuse to advance until the
previous phase's artifacts exist.

### Phase A — Contract Extraction

**Goal:** Produce a machine-checkable description of what the source system _promises_, independent
of how it is implemented.

**Required artifacts:**

- `contract/` directory in the new project, containing:
  - **CLI contract** (if applicable):
    - `cli-surface.md` — every command, subcommand, flag (short/long), argument, default,
      required/optional status, environment-variable bindings, config-file precedence.
    - `exit-codes.md` — every documented exit code and its meaning.
    - `stdout-stderr-shape.md` — output formats (plain, JSON, table), colorization rules,
      TTY/non-TTY behavior, locale handling, line endings.
    - `help-text/` — captured `--help` output for every command, as golden fixtures.
  - **Service / API contract** (if applicable):
    - `openapi.yaml` (or `.json`) for HTTP, `*.proto` for gRPC, GraphQL SDL, AsyncAPI for messaging.
    - `error-payloads.md` — error shapes, status codes, idempotency semantics.
    - `headers.md` — auth, content-type, custom headers, rate-limit semantics.
  - **Data contracts** (if applicable):
    - `on-disk-formats.md` — file formats, layouts, compatibility windows.
    - `wire-formats.md` — network protocols, framing, versioning.
    - `db-schemas/` — DDL or schema-extraction output.
    - `config-schema.json` — JSON Schema of any config file.
  - **Compatibility envelope:**
    - `semver-promises.md` — what is considered breaking vs. additive; current version; what cannot
      change.
    - `parity-boundary.md` — explicit list of behaviors the rewrite will **not** preserve (justified
      with ADR links).
- `adr/` directory initialized with `0001-rewrite-decision.md` and `0002-parity-boundary.md`.

**How to extract:**

1. Read user-facing docs, `--help` output, man pages, README.
1. Capture every documented exit code; capture every documented HTTP status. Run the source binary
   against representative inputs and record outputs.
1. For HTTP services, capture production traffic with mitmproxy/ GoReplay/WireMock if possible.
1. For libraries with public APIs, list every exported symbol and its documented contract.
1. Treat **observed behavior** as authoritative when it diverges from documented behavior — users
   depend on what the system does, not what the docs say (see Chesterton's Fence in
   [§7](#7-anti-patterns--failure-modes-named-in-the-literature)).

**Gate:** No source-code reading for design purposes until Phase A artifacts are present and
reviewed.

### Phase B — Freeze Behavior (Characterization Tests Against the Source)

**Goal:** Lock current observable behavior into automated, machine-runnable tests that pass against
the **source** today and will later be required to pass against the **target**.

**Required artifacts:**

- `parity-tests/` directory containing:
  - **Golden / approval tests** for CLI: every documented command invocation with
    stdout/stderr/exit-code fixtures. Use `bats-core` / `cram` / `trycmd` / `insta` /
    `ApprovalTests` according to host language for the harness.
  - **HTTP/wire replay tests**: recorded cassettes (VCR) or deterministic mocks (WireMock).
  - **Characterization unit tests** for any library API: each public function called with
    representative inputs, observed output pinned.
  - **Property tests** (where invariants exist): defined in language-neutral terms so the same suite
    can be re-implemented against the target. Frameworks: Hypothesis (Python), proptest (Rust),
    QuickCheck (Rust/Haskell), fast-check (JS/TS).
- All tests **must pass against the source** before Phase C begins.
- A **coverage report** of the parity tests against the contract — identifying which parts of the
  contract are covered by parity tests vs. which are documentation-only.

**Gate:** Parity tests green against the source. Coverage gaps in the contract are explicitly
accepted (with ADR) or filled before Phase C.

### Phase C — Idiomatic Design (From the Contract, Without the Source Code)

**Goal:** Produce a design for the new system using only the contract and the target language's
idioms. The source code is **not an input**.

**Required artifacts:**

- `design/` directory containing:
  - `architecture.md` — module layout, key abstractions, error model, concurrency model, I/O model,
    dependency choices. Must justify each choice by reference to:
    1. A specific contract requirement, AND
    1. A specific target-language idiom guideline (Effective Go, Rust API Guidelines, PEP 8/20, .NET
       Framework Design Guidelines, Kotlin coding conventions, Google C++ Style Guide, C++ Core
       Guidelines, …).
  - `dependencies.md` — chosen libraries with rationale (prefer target-ecosystem idiomatic
    libraries; e.g., `clap` for Rust CLI, `cobra` for Go CLI, `click`/`typer` for Python CLI,
    `oclif` for Node CLI).
  - `error-model.md` — designed natively for the target (Go's explicit `error` returns and
    `errors.Is/As`; Rust's `Result<T, E>` with `?` and `thiserror`/`anyhow`; Python exceptions with
    explicit hierarchy; etc.). May **not** mirror the source error model 1:1.
  - `concurrency-model.md` — designed natively (goroutines/channels, `tokio`/`async-std`,
    `asyncio`/`trio`, JVM virtual threads, Node event loop, …). May **not** mirror the source.
  - ADRs (`adr/0003-*`, `0004-*`, …) for every non-trivial choice.

**Rule of separation:** Phase C may read the contract artifacts from Phase A and the target-language
style guides. It **may not** read the source code. This is the most important guardrail in the whole
model; it is the single highest-leverage step for preventing transliteration.

**Gate:** Design is reviewed against the contract (every contract requirement maps to a design
element) and against the target-language canon (every design element justified by an idiom).

### Phase D — Implementation Under Anti-Transliteration Guardrails

**Goal:** Write the new implementation, idiomatically, against the design.

**Mandatory guardrails (refusal rules for AI agents):**

- The agent **must refuse** to "translate function X from source to target". The valid request is
  "implement contract feature Y per the design".
- The agent **must refuse** to keep source-side variable names, function names, module names, or
  directory names unless they happen to match target idioms.
- The agent **must refuse** to emit code patterns from the source language's style when an idiomatic
  target equivalent exists. See [§6 refusal list](#6-refusal-list-translation-smells-to-reject) for
  concrete examples.
- The agent **must consult** the target-language style guide for every non-trivial construct.
- The agent **must emit a parity test alongside every implemented contract feature**, before merging
  it.

**Implementation-time review pass (per change):**

- Does this code look like source-language code mechanically converted into target syntax? If yes —
  redesign.
- Are error paths idiomatic to the target?
- Is concurrency expressed in target primitives?
- Are public types/names target-idiomatic?
- Are dependencies target-ecosystem-native?

### Phase E — Differential, Property, Fuzz, Shadow Validation

**Goal:** Prove the target's observable behavior matches the source's across all parity-test
classes.

**Required artifacts and runs:**

- **Golden / approval tests:** the Phase-B suite passes byte-for-byte against the target (with
  documented, ADR-justified diffs only).
- **Property tests:** the Phase-B property suite passes against the target with at least the same
  input-space coverage.
- **Differential tests:** for each parity-relevant function/route, run the same inputs against
  source and target and assert equivalence. Use \[Trail of Bits **DIFFER**\] for transformed-program
  differential testing where applicable.
- **Fuzz campaign:** coverage-guided fuzzing (AFL++, libFuzzer, cargo-fuzz, jazzer, OSS-Fuzz harness
  if appropriate) for at least the duration committed in `parity-boundary.md`. No crashes; no
  divergence from source on any minimized input.
- **Shadow traffic** (for services): tee production traffic to the new implementation; log diffs;
  investigate every divergence; resolve or ADR.
- **Performance baseline:** measured against the source for the representative workloads in
  `parity-tests/perf/`. Regressions outside the documented envelope block cutover.

**Gate:** All parity tests green; fuzz campaign clean; shadow traffic divergences resolved;
performance within envelope.

### Phase F — Parallel-Run, Canary, Cutover, Decommission

**Goal:** Move traffic from source to target with rollback at every step.

**Required artifacts and steps:**

1. **Parallel-run** (a.k.a. dark launch): both implementations process traffic; only source's
   responses are user-visible; target's responses are logged and diffed. Run until divergence rate
   is acceptable.
1. **Canary**: route a small percentage (1–5%) of user traffic to the target. Monitor error rate,
   latency, resource usage. Roll back on regression.
1. **Progressive rollout**: 5% → 25% → 50% → 100%, gated by SLO adherence at each step.
1. **Cutover**: source goes read-only / off; target is the system of record.
1. **Rollback plan**: at every step, a documented, tested procedure to revert traffic to the source.
1. **Decommission**: after a confidence period (days–weeks), remove source code from the repo and
   announce end-of-life. Capture lessons in `adr/9999-postmortem.md`.

**Gate:** Cutover is irreversible only after the confidence period; until then, rollback must remain
possible.

---

## 4. Strategy Patterns (When to Use Which)

| Pattern                          | When to use                                                                                                                                                                                                            | Reference                                                                                                                                                                  |
| -------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Strangler Fig**                | Long-lived production system; cannot stop the world; replace component-by-component behind a routing seam. Default for services.                                                                                       | https://martinfowler.com/bliki/StranglerFigApplication.html · https://martinfowler.com/articles/2024-strangler-fig-rewrite.html                                            |
| **Branch by Abstraction**        | Inside one codebase: introduce an abstraction over the part being rewritten; ship old and new behind a flag; flip. Default for libraries / monoliths being modernized in-place.                                        | https://martinfowler.com/bliki/BranchByAbstraction.html · https://docs.aws.amazon.com/prescriptive-guidance/modernization-decomposing-monoliths/branch-by-abstraction.html |
| **Parallel Run**                 | The rewrite must prove behavioral equivalence under live traffic before cutover.                                                                                                                                       | https://engineering.zalando.com/posts/2021/11/parallel-run.html                                                                                                            |
| **Traffic Shadowing**            | Service rewrites; replay production traffic against the new implementation without user impact.                                                                                                                        | https://emissary-ingress.dev/docs/3.9/topics/using/shadowing/ · https://www.envoyproxy.io/docs/envoy/latest/configuration/http/http_conn_man/traffic_splitting.html        |
| **Canary / Progressive rollout** | Final cutover step.                                                                                                                                                                                                    | https://goreplay.org/blog/canary-deployment-strategy-20250808133113/                                                                                                       |
| **Big-bang rewrite**             | **Default-prohibited.** Allowed only when the system is small enough that the entire rewrite fits in one parity-test gated cycle, and when there is no live production traffic to migrate. Document explicitly in ADR. | https://www.joelonsoftware.com/2000/04/06/things-you-should-never-do-part-i/                                                                                               |

**Migrations playbook (Larson):** _Derisk → Enable → Finish._ A migration that has not been finished
is a migration that is generating ongoing cost. Plan the _Finish_ before starting the _Derisk_.
https://lethain.com/migrations/

---

## 5. Idiomatic Target-Language Canon (Pointer Table)

The guideline stays language-agnostic; the agent must consult the target's canonical references for
every non-trivial idiom choice in Phase C and D.

| Target                         | Canonical references                                                                                                                                                                                                         |
| ------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Go**                         | Effective Go — https://go.dev/doc/effective_go (note its explicit "a straightforward translation from C++ or Java into Go is unlikely to be satisfactory"); Go Code Review Comments — https://go.dev/wiki/CodeReviewComments |
| **Rust**                       | Rust API Guidelines — https://rust-lang.github.io/api-guidelines/ ; Rust Style Guide — https://doc.rust-lang.org/1.0.0/style/ ; _Rust for Rustaceans_ (Gjengset)                                                             |
| **Python**                     | PEP 8 — https://peps.python.org/pep-0008/ ; PEP 20 (Zen) — https://peps.python.org/pep-0020/ ; Google Python Style Guide — https://google.github.io/styleguide/pyguide.html                                                  |
| **TypeScript / JavaScript**    | TypeScript Deep Dive — https://basarat.gitbook.io/typescript ; Microsoft TS coding guidelines (internal); Node.js best practices — https://github.com/goldbergyoni/nodebestpractices                                         |
| **.NET / C#**                  | Framework Design Guidelines — https://learn.microsoft.com/en-us/dotnet/standard/design-guidelines/                                                                                                                           |
| **Kotlin**                     | Coding conventions — https://kotlinlang.org/docs/coding-conventions.html ; _Effective Java_ (Bloch) for JVM heritage                                                                                                         |
| **Java**                       | _Effective Java_ (Bloch); Google Java Style — https://google.github.io/styleguide/javaguide.html                                                                                                                             |
| **C++**                        | Google C++ Style Guide — https://google.github.io/styleguide/cppguide.html ; C++ Core Guidelines — https://github.com/isocpp/CppCoreGuidelines                                                                               |
| **Scala**                      | Scala Style Guide — https://docs.scala-lang.org/style/                                                                                                                                                                       |
| **Bash (target)**              | Google Shell Style Guide — https://google.github.io/styleguide/shellguide.html ; shellcheck rules                                                                                                                            |
| **CLI design (cross-cutting)** | CLI Guidelines — https://clig.dev/                                                                                                                                                                                           |

---

## 6. Refusal List (Translation Smells to Reject)

The agent **must refuse to emit, and must flag in review**, any of the following. Each item is named
so reviewers can cite the specific smell.

1. **Class-hierarchy-as-trait-hierarchy.** Mirroring a deep inheritance tree from an OOP source into
   Rust traits, Go interfaces, or Haskell typeclasses 1:1. Re-derive the abstraction from the
   contract.
1. **Shell-pipeline-as-subprocess-chain.** Re-implementing a Bash pipeline (`a | b | c`) by spawning
   `a`, `b`, `c` as subprocesses in the target. The target should do the I/O natively.
1. **Exception-to-Result mechanical mapping.** Wrapping every try/except in `Result<T, E>` (or vice
   versa) without redesigning what is actually a recoverable error vs. a bug vs. a logic
   precondition.
1. **GIL-shaped concurrency in a non-GIL target.** Carrying over Python's "one big lock + threads"
   model into Go/Rust, where the idiomatic model is goroutines/channels or `tokio` tasks.
1. **Callback chains where async/await fits.** Translating a JS callback-style API into the target
   without using the target's native async primitives.
1. **Getter/setter methods in Go.** Go uses direct field access for public fields, named accessors
   only when behavior is non-trivial.
1. **`Vec<Box<dyn Trait>>` mirroring a Java `List<Interface>` when a sum type (enum) is what the
   domain actually has.**
1. **`null`/`None` everywhere instead of typed absence.** Rust `Option<T>`, Kotlin nullable types,
   TS strict-null-checks should carry semantic weight, not be a syntactic translation of
   `someVar == null` checks.
1. **String-typed configuration.** If the source passed config as stringly-typed env vars, the
   target should parse them into a typed config struct at startup.
1. **Source-side directory names / module names / file names** in the target tree when those names
   violate target conventions (e.g., `utils/` and `helpers/` in Go; PascalCase files in snake_case
   ecosystems).
1. **Mirrored test structure.** Translating the source's test files 1:1 instead of writing
   target-idiomatic tests against the parity contract.
1. **Comments translated verbatim.** Source-language comments explaining source-side idioms are
   often nonsense in the target language.
1. **Re-creating shell-isms in higher-level targets.** Re-implementing `find`, `grep`, `xargs`,
   `sed` calls as subprocess invocations when the target ecosystem has native libraries (e.g.,
   `walkdir`, `regex`, `serde_json` in Rust; `pathlib`, `re`, `json` in Python).
1. **Hand-rolled CLI parsing translated from `getopts`/`argparse`.** Use the target's idiomatic CLI
   library (`clap`, `cobra`, `click`, `oclif`, `picocli`).
1. **Mirroring the source's serialization format choices when the contract permits change.**
   (Caveat: the contract often does _not_ permit change. Check Phase A.)
1. **Logging strings instead of structured fields** in a target that has structured logging (Go's
   `slog`, Rust's `tracing`, Python's `structlog`).

---

## 7. Anti-Patterns / Failure Modes Named in the Literature

- **Transliteration smell** ("Java in Go", "C in Rust"). Effective Go explicitly warns against it.
  https://www.gocloudstudio.com/post/writing-idiomatic-go-patterns-that-separate-clean-code-from-java-in-go/
- **Second-system effect** (Brooks, _Mythical Man-Month_). The rewrite becomes the dumping ground
  for every deferred improvement, generalization, and feature. Result: bloated, late, and worse than
  the system it replaces. https://en.wikipedia.org/wiki/Second-system_effect ·
  https://albrightlabs.com/blog/avoiding-second-system-syndrome-in-code-rewrites/
- **Chesterton's Fence.** Legacy code often contains seemingly pointless logic that actually encodes
  a hard-won bug fix or regulatory requirement. Removing it silently reintroduces the bug.
  Characterization tests (Phase B) are the antidote.
  https://alexkondov.com/legacy-code-and-chestersons-fence/ ·
  https://fourweekmba.com/the-chestertons-fence-problem-ai-removing-things-it-doesnt-understand/
- **Undocumented-behavior surprise.** Users depend on observed behavior, not documented behavior.
  Mitigation: golden tests + shadow traffic + extended dual-run.
- **Scope creep during rewrite.** Mitigation: enforce Larson's derisk/enable/finish gates and the
  "no new features" rule in [§0](#0-non-negotiables-read-this-section-first).
  https://lethain.com/migrations/ · https://en.wikipedia.org/wiki/Scope_creep
- **Joel Spolsky's warning** ("Things You Should Never Do, Part I"). Big-bang rewrites discard
  accumulated bug fixes and burn schedule. This guideline treats it as a _constraint to mitigate_,
  not a veto: Strangler Fig + characterization tests + parallel-run address the specific failure
  mode Joel named. https://www.joelonsoftware.com/2000/04/06/things-you-should-never-do-part-i/
- **LLM-specific failure modes.** Per IBM/ICSE 2024 _Lost in Translation_: 15 categories of bugs
  introduced by LLMs translating code, with correct-translation rates between 2.1% and 47.3%
  depending on model and language pair. Categories include type mismatches, missing error handling,
  semantic gaps (e.g., integer overflow semantics differ between Java and C), and hallucinated
  target APIs. https://arxiv.org/abs/2308.03109
- **Semantic gap blindness.** Java integer arithmetic is defined modulo 2³²; naive C translation
  introduces UB. Java/C# `String` immutability differs from C `char*`. JS `==` vs. `===`. The agent
  must check for semantic-gap categories per the target/source pair.
  https://www2.eecs.berkeley.edu/Pubs/TechRpts/2025/EECS-2025-174.pdf
- **Evaluation-harness false positives.** A test suite written against the target may "pass" while
  still violating the source contract, because the test author transliterated the test too. Parity
  tests must be **derived from the contract**, not from the source tests.
  https://arxiv.org/abs/2605.02195

---

## 8. AI-Agent Prompting Tactics (To Be Embedded When This Doc Is Loaded)

When this guideline is loaded into an AI agent's context, the agent should additionally apply these
meta-tactics. These tactics are synthesized from Anthropic's and OpenAI's published
prompt-engineering guidance and from the LLM-translation literature.

1. **Two-step prompting (extract → design).** First prompt extracts the contract. Second prompt
   designs from the contract — _and the second prompt does not include the source code in its
   context_. This separation is the single highest-leverage mitigation for transliteration.
1. **Affirmative idiom anchors beat negative rules.** "Use the `?` operator and `thiserror`-style
   enum errors" outperforms "don't translate try/except literally." Pair each refusal in
   [§6](#6-refusal-list-translation-smells-to-reject) with an affirmative idiom.
1. **Permission to say "I don't know".** For ambiguous contract gaps, require the agent to ask a
   clarification question rather than guess. The contract is authoritative; if it is silent, the
   human decides.
1. **Two-pass review.**
   - **Pass 1:** correctness against parity tests.
   - **Pass 2:** translation-smell review against
     [§6 refusal list](#6-refusal-list-translation-smells-to-reject). Frame: "Pretend you do not
     know what language this was originally written in. Does this code look like idiomatic
     [target]?"
1. **Differential-by-construction.** Every implemented feature ships with the parity test that pins
   it. No code without its test.
1. **Chain-of-thought scaffold in the prompt.**
   `extract → freeze → design → implement → verify → review`. Make the phase explicit in every
   interaction.
1. **Few-shot exemplars of idiomatic target code** beat abstract style-guide pointers. Include 1–3
   high-quality target-language snippets at the start of Phase C and D.
1. **Architectural context as XML/structured blocks.** Wrap the contract, the design, and the
   implementation request in clearly delineated structured sections so the agent does not conflate
   "what to build" with "how the source built it."

References:

- Anthropic prompt engineering best practices —
  https://docs.anthropic.com/en/docs/build-with-claude/prompt-engineering/claude-4-best-practices
- Claude Code best practices — https://www.anthropic.com/engineering/claude-code-best-practices
- Claude Code sub-agents — https://docs.anthropic.com/en/docs/claude-code/sub-agents
- OpenAI Codex prompting — https://developers.openai.com/codex/prompting
- OpenAI code generation guide — https://developers.openai.com/api/docs/guides/code-generation
- GitHub Copilot custom instructions —
  https://docs.github.com/en/copilot/reference/custom-instructions-support

---

## 9. Verification Tooling Roster

The following tools are recommended (use the target language's ecosystem-native pick where
available; do not transliterate the harness either).

### CLI parity / golden / approval tests

- **bats-core** (Bash) — https://bats-core.readthedocs.io/
- **cram** (language-agnostic CLI snapshot) — https://bitheap.org/cram/
- **trycmd** (Rust) — https://docs.rs/trycmd
- **insta** (Rust snapshot) — https://insta.rs/ · https://github.com/mitsuhiko/insta
- **ApprovalTests** (multi-language) — https://approvaltests.com/
- **expect** (interactive CLI automation) — Tcl-based, classic

### Property-based testing

- **Hypothesis** (Python) — https://hypothesis.readthedocs.io/
- **proptest** (Rust) — https://docs.rs/proptest
- **QuickCheck** (Rust/Haskell) — https://github.com/BurntSushi/quickcheck ·
  https://hackage.haskell.org/package/QuickCheck
- **fast-check** (JS/TS) — https://fast-check.dev/
- **jqwik** (JVM) — https://jqwik.net/

### Coverage-guided fuzzing

- **AFL++** — https://aflplus.plus/
- **libFuzzer** — https://llvm.org/docs/LibFuzzer.html
- **cargo-fuzz** (Rust) — https://rust-fuzz.github.io/book/cargo-fuzz.html
- **jazzer** (JVM) — https://github.com/CodeIntelligenceTesting/jazzer
- **OSS-Fuzz** (hosted continuous fuzzing) — https://google.github.io/oss-fuzz/

### Differential testing of transformed/translated programs

- **DIFFER** (Trail of Bits) — directly aimed at validating transformed/rewritten programs.
  https://blog.trailofbits.com/2024/01/31/introducing-differ-a-new-tool-for-testing-and-validating-transformed-programs/

### HTTP record / replay / shadow

- **VCR.py** (Python) — https://vcrpy.readthedocs.io/
- **WireMock** — https://wiremock.org/docs/
- **mitmproxy** — https://docs.mitmproxy.org/stable/
- **GoReplay** — https://goreplay.org/ · https://goreplay.org/shadow-testing/

### API / schema contract diffing

- **Pact** (consumer-driven contracts) — https://docs.pact.io/
- **openapi-diff** — https://github.com/OpenAPITools/openapi-diff
- **cargo-semver-checks** (Rust) — https://github.com/obi1kenobi/cargo-semver-checks
- **JSON Schema** — https://json-schema.org/specification
- **OpenAPI** — https://spec.openapis.org/oas/latest
- **semver** — https://semver.org/

### Distributed-system conformance

- **Jepsen** — https://jepsen.io/ · https://jepsen.io/consistency/models/sequential

### Decision capture

- **ADR (Nygard template)** —
  https://www.cognitect.com/blog/2011/11/15/documenting-architecture-decisions
- **MADR (Markdown ADR)** — https://adr.github.io/madr/ · https://adr.github.io/
- **adr-tools** — https://github.com/npryce/adr-tools

---

## 10. Case Studies Worth Citing

A short list of real cross-language rewrites with primary-source writeups. Use as design exemplars
and in ADR justification.

| Project                         | Move                                | Lesson                                                                                                                                          | Source                                                                                               |
| ------------------------------- | ----------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| **Discord Read States**         | Go → Rust                           | Preserved service API; Rust's memory model eliminated GC-induced tail-latency spikes. Initial port was deliberately rough, then redesigned.     | https://discord.com/blog/why-discord-is-switching-from-go-to-rust                                    |
| **Cloudflare Pingora**          | NGINX/C → Rust                      | New proxy framework; preserved external behavior of the L7 platform, redesigned the substrate.                                                  | https://blog.cloudflare.com/how-we-built-pingora-the-proxy-that-connects-cloudflare-to-the-internet  |
| **Cloudflare ROFL**             | NGINX module (C/Lua) → Rust         | Drop-in replacement at the operator level; idiomatic Rust internally.                                                                           | https://blog.cloudflare.com/rust-nginx-module                                                        |
| **Cloudflare FL2**              | NGINX/LuaJIT → Rust                 | Major substrate replacement under a stable platform contract.                                                                                   | https://blog.cloudflare.com/it-it/20-percent-internet-upgrade/                                       |
| **Mozilla Stylo / Quantum CSS** | C++ → Rust                          | Incremental in-tree replacement of a hot subsystem (CSS engine), Quantum project.                                                               | https://hacks.mozilla.org/2017/08/inside-a-super-fast-css-engine-quantum-css-aka-stylo/              |
| **Astral `ruff`**               | Python lint tooling → Rust          | Single tool replacing Flake8 + ~90 plugins, Black, isort, etc. Preserved CLI/config contracts of the originals.                                 | https://github.com/astral-sh/ruff                                                                    |
| **Astral `uv`**                 | pip/virtualenv/Poetry/pipenv → Rust | Replaced the Python packaging stack with a single Rust tool; preserved workflow contract.                                                       | https://github.com/astral-sh/uv · https://astral.sh/blog/uv-unified-python-packaging                 |
| **esbuild**                     | JS bundler tooling → Go             | Workflow preservation, internal redesign. FAQ explicitly documents intentional behavioral differences.                                          | https://esbuild.github.io/faq/                                                                       |
| **swc, oxc, biome, Bun**        | JS/TS tooling → Rust / Zig          | Same pattern: preserve developer workflow, redesign substrate.                                                                                  | https://swc.rs/ · https://oxc.rs/ · https://biomejs.dev/blog/annoucing-biome/ · https://bun.com/docs |
| **Deno 2**                      | —                                   | Explicitly _not_ a Node clone in Rust. Useful as a stated parity-boundary example.                                                              | https://deno.com/blog/v2.0                                                                           |
| **ripgrep**                     | grep replacement, Rust              | Intentionally **not** a drop-in `grep`. Cite as a parity-boundary example: where deviation from source behavior is a _design goal_, declare it. | https://github.com/BurntSushi/ripgrep/blob/master/FAQ.md · https://burntsushi.net/ripgrep/           |
| **fd**                          | find replacement, Rust              | Default-case-insensitive, respects `.gitignore`. Same parity-boundary lesson as ripgrep.                                                        | https://github.com/sharkdp/fd                                                                        |
| **eza**                         | ls replacement, Rust                | Same parity-boundary lesson; modern defaults.                                                                                                   | https://eza.rocks/ · https://github.com/eza-community/eza                                            |
| **bat**                         | cat with syntax highlighting, Rust  | Preserves piping/redirection contract; adds modern features when TTY.                                                                           | https://github.com/sharkdp/bat                                                                       |
| **gitoxide**                    | git internals, Rust                 | Idiomatic pure-Rust Git; deliberately not a transliteration of C.                                                                               | https://github.com/GitoxideLabs/gitoxide                                                             |

**Negative / cautionary:**

- **Netscape 6 / Mozilla** (the original "Things You Should Never Do" case) — big-bang rewrite,
  multi-year delay, market loss.
  https://www.joelonsoftware.com/2000/04/06/things-you-should-never-do-part-i/

**Caveat — Dropbox Magic Pocket "Go → Rust" rewrite:** widely cited in secondary sources but **no
primary Dropbox post** explicitly frames Magic Pocket as a Go-to-Rust _rewrite_. Cite the primary
Magic Pocket posts for storage-design context and the QCon talk for the Rust optimization angle
only:

- https://dropbox.tech/tech/2016/05/inside-the-magic-pocket/
- https://qconsf.com/sf2016/sf2016/presentation/going-rust-optimizing-storage-dropbox.html

---

## 11. LLM Code Translation: Research Findings

Findings the agent should internalize _before_ a rewrite, not learn from regression.

- **Lost in Translation** (IBM, ICSE 2024). 1,700 code samples, multiple LLMs, 5 languages.
  Correct-translation rates: 2.1% to 47.3%. **15 categories** of translation bugs identified (type
  mismatches, logic errors, missing error handling, semantic gaps, hallucinated APIs, …). Targeted
  prompt-crafting addressing specific symptom categories improved performance ~5.5% on average.
  https://arxiv.org/abs/2308.03109 ·
  https://research.ibm.com/publications/lost-in-translation-a-study-of-bugs-introduced-by-large-language-models-while-translating-code
  · https://github.com/Intelligent-CAT-Lab/PLTranslationEmpirical
- **Migrating Code At Scale With LLMs At Google** (2025). 39 migrations over 12 months, 595 changes,
  93,574 edits, 74.45% generated by LLM, ~50% time savings reported by developers. Methodology: find
  migration points → LLM generates fix → validate against tests → iterate. Key takeaway: success is
  gated on the _validation_ loop, not on raw generation. https://arxiv.org/abs/2504.09691
- **LLM-Based Code Translation Needs Formal Compositional Reasoning** (UC Berkeley, 2025). LLMs fail
  predictably on semantic gaps (e.g., Java mod-2³² integer arithmetic vs. C undefined behavior).
  Proposes a **feature-mapping** approach: predefined translation rules for known-hard primitives,
  with static checks enforcing compliance. Hybrid rule-based + LLM beats LLM-only.
  https://www2.eecs.berkeley.edu/Pubs/TechRpts/2025/EECS-2025-174.pdf
- **Semantic Alignment-Enhanced Code Translation** — https://arxiv.org/pdf/2409.19894
- **Scalable, Validated Code Translation of Entire Projects** (Amazon Science) —
  https://assets.amazon.science/0e/ab/c10459dd4013a7c02f09b8c96f3f/scalable-validated-code-translation-of-entire-projects-using-large-language-models.pdf
- **TransCoder** (Meta, NeurIPS 2020) — unsupervised cross-language translation baseline. Useful as
  historical context. https://arxiv.org/abs/2006.03511 ·
  https://github.com/facebookresearch/TransCoder

**Operational consequence:** the parity-test gate in Phase E is _not optional_. The published
correct-translation rates make unsupervised LLM rewrites untrustworthy by default; the parity tests
are what move the rewrite from "plausible code" to "verified rewrite".

---

## 12. Agent Skill / Prompt Libraries to Study

For authoring this guideline into agent-specific skill files (`SKILL.md`, `.cursor/rules/*.mdc`,
`.clinerules`, Copilot custom instructions), study these established libraries first. The official
ones in particular are structural templates worth modeling after.

- **Anthropic Claude Code skills (official)** — https://github.com/anthropics/skills
- **Anthropic Claude cookbooks (official)** — https://github.com/anthropics/claude-cookbooks
- **Claude Code skills docs** — https://code.claude.com/docs/en/skills
- **OpenAI Codex skills (official)** — https://github.com/openai/codex
- **OpenAI `migrate-to-codex` skill** (official; useful as a structural template for a
  migration-flavored skill) —
  https://github.com/openai/skills/blob/main/skills/.curated/migrate-to-codex/SKILL.md
- **Awesome Claude Code** — https://github.com/jqueryscript/awesome-claude-code
- **Awesome Claude Skills** — https://github.com/travisvn/awesome-claude-skills ·
  https://awesomeclaudeskills.com/
- **Awesome Cursor Rules** — https://github.com/PatrickJS/awesome-cursorrules ·
  https://dotcursorrules.com/
- **Cursor refactoring workshop** —
  https://cursor.com/workshops/recording/refactoring-legacy-codebases
- **Cline prompts repo** — https://github.com/cline/prompts ·
  https://thepromptshelf.dev/blog/cline-rules-complete-guide-2026/
- **Aider** — https://aider.chat/ · https://blog.netnerds.net/2024/10/aider-is-awesome/
- **GitHub Copilot customization** —
  https://docs.github.com/en/copilot/how-tos/copilot-on-github/customize-copilot/customize-copilot-overview
  · https://docs.github.com/en/copilot/reference/custom-instructions-support

---

## 13. Recommended Repository Layout for a Rewrite

A target-side directory layout that operationalizes this guideline. Adapt names to target
conventions.

```
new-project/
├── contract/                       # Phase A artifacts
│   ├── cli-surface.md
│   ├── exit-codes.md
│   ├── stdout-stderr-shape.md
│   ├── help-text/
│   ├── openapi.yaml
│   ├── error-payloads.md
│   ├── headers.md
│   ├── on-disk-formats.md
│   ├── wire-formats.md
│   ├── db-schemas/
│   ├── config-schema.json
│   ├── semver-promises.md
│   └── parity-boundary.md
├── parity-tests/                   # Phase B artifacts
│   ├── golden/                     # CLI golden / approval
│   ├── replay/                     # HTTP / wire cassettes
│   ├── characterization/           # library-API characterization
│   ├── property/                   # language-neutral property suite
│   ├── differential/               # source-vs-target diff harness
│   ├── fuzz/                       # fuzz corpora & harnesses
│   └── perf/                       # baseline workloads
├── design/                         # Phase C artifacts
│   ├── architecture.md
│   ├── dependencies.md
│   ├── error-model.md
│   └── concurrency-model.md
├── adr/                            # ADRs (Nygard / MADR)
│   ├── 0001-rewrite-decision.md
│   ├── 0002-parity-boundary.md
│   ├── 0003-target-language-choice.md
│   └── ...
├── src/                            # Phase D — target-idiomatic
└── ...                             # target-ecosystem-native rest
```

---

## 14. Top 15 Load-Bearing References (Citation Anchors)

For ADR justification and review citations. These are the URLs an agent should default to when
grounding a rewrite decision.

1. https://martinfowler.com/bliki/StranglerFigApplication.html — Strangler Fig
1. https://martinfowler.com/bliki/BranchByAbstraction.html — Branch by Abstraction
1. https://www.joelonsoftware.com/2000/04/06/things-you-should-never-do-part-i/ — Spolsky's warning
1. https://understandlegacycode.com/blog/key-points-of-working-effectively-with-legacy-code/ —
   Feathers, _Working Effectively with Legacy Code_
1. https://lethain.com/migrations/ — Larson, derisk/enable/finish
1. https://discord.com/blog/why-discord-is-switching-from-go-to-rust — Discord Go→Rust case study
1. https://arxiv.org/abs/2308.03109 — _Lost in Translation_ (ICSE 2024)
1. https://arxiv.org/abs/2504.09691 — Google: Migrating Code at Scale with LLMs
1. https://www2.eecs.berkeley.edu/Pubs/TechRpts/2025/EECS-2025-174.pdf — Formal Compositional
   Reasoning
1. https://blog.trailofbits.com/2024/01/31/introducing-differ-a-new-tool-for-testing-and-validating-transformed-programs/
   — DIFFER
1. https://go.dev/doc/effective_go — Effective Go (canonical anti-transliteration statement)
1. https://rust-lang.github.io/api-guidelines/ — Rust API Guidelines
1. https://clig.dev/ — CLI Guidelines
1. https://approvaltests.com/ — Approval / golden testing
1. https://github.com/openai/skills/blob/main/skills/.curated/migrate-to-codex/SKILL.md — official
   migration-flavored skill template

---

## 15. Full Reference Library

Grouped by topic for fast lookup during a rewrite.

> **Citation provenance — reviewers read this first.** Every academic citation (arXiv ID, DOI,
> tech-report) in §14–§15 was fetched and confirmed to resolve to its stated title as of
> **2026-06-15**; the per-paper verification ledger is in [`SOURCES.md`](./SOURCES.md). This
> guideline tracks 2025–2026 research, so several citations **postdate common LLM training
> cutoffs**. **Do not flag a citation as fabricated or "hallucinated" solely because its arXiv ID is
> future-dated — fetch the URL and verify before flagging.** Examples that have tripped this up:
> `arXiv:2605.02195` (_Beyond Translation Accuracy_) and `arXiv:2605.07001` (_SmellBench_) — both
> May 2026, both real.

### Strategy & process

- Strangler Fig (Fowler) — https://martinfowler.com/bliki/StranglerFigApplication.html
- Strangler Fig — original — https://martinfowler.com/bliki/OriginalStranglerFigApplication.html
- Strangler Fig — 2024 update — https://martinfowler.com/articles/2024-strangler-fig-rewrite.html
- AWS Prescriptive Guidance: Strangler Fig —
  https://docs.aws.amazon.com/prescriptive-guidance/cloud-design-patterns/strangler-fig.html
- Branch by Abstraction (Fowler) — https://martinfowler.com/bliki/BranchByAbstraction.html
- AWS Prescriptive Guidance: Branch by Abstraction —
  https://docs.aws.amazon.com/prescriptive-guidance/modernization-decomposing-monoliths/branch-by-abstraction.html
- Confluent: Branch by Abstraction for Event-Driven Microservices —
  https://developer.confluent.io/courses/microservices/branch-by-abstraction/
- microservices.io: Strangler Application —
  https://microservices.io/patterns/refactoring/strangler-application.html
- Spolsky, "Things You Should Never Do, Part I" —
  https://www.joelonsoftware.com/2000/04/06/things-you-should-never-do-part-i/
- Counter: Eon, "Something You Should Rarely Do" —
  https://medium.com/@kolorahl/something-you-should-rarely-do-fbec8cd1b89
- Counter: Schwartzer, "Joel is Wrong" —
  https://medium.com/cyberark-engineering/joel-is-wrong-and-it-costs-you-a-fortune-105924be8f01
- Larson, "Migrations: the sole scalable fix to tech debt" — https://lethain.com/migrations/
- ThoughtWorks Tech Radar: AI for code migrations —
  https://www.thoughtworks.com/radar/techniques/ai-for-code-migrations
- Zalando parallel-run — https://engineering.zalando.com/posts/2021/11/parallel-run.html
- Emissary traffic shadowing — https://emissary-ingress.dev/docs/3.9/topics/using/shadowing/
- Envoy traffic splitting —
  https://www.envoyproxy.io/docs/envoy/latest/configuration/http/http_conn_man/traffic_splitting.html
- GoReplay shadow testing — https://goreplay.org/shadow-testing/
- GoReplay canary strategy — https://goreplay.org/blog/canary-deployment-strategy-20250808133113/
- Charity Majors on rewrites & observability —
  https://blog.container-solutions.com/charity-majors-on-code-rewrites-observability-and-team-performance

### Characterization & contract preservation

- Feathers, _Working Effectively with Legacy Code_ (summary) —
  https://understandlegacycode.com/blog/key-points-of-working-effectively-with-legacy-code/
- Characterization test (Wikipedia) — https://en.wikipedia.org/wiki/Characterization_test
- DeadTech: Characterization tests — https://daedtech.com/characterization-tests/
- Honeybadger: Ruby legacy characterization tests —
  https://www.honeybadger.io/blog/ruby-legacy-characterization-test/
- ApprovalTests — https://approvaltests.com/
- Pact (consumer-driven contracts) — https://docs.pact.io/
- Pact: How it works — https://docs.pact.io/getting_started/how_pact_works
- openapi-diff — https://github.com/OpenAPITools/openapi-diff
- cargo-semver-checks — https://github.com/obi1kenobi/cargo-semver-checks
- semver — https://semver.org/
- OpenAPI spec — https://spec.openapis.org/oas/latest
- JSON Schema — https://json-schema.org/specification
- Jepsen — https://jepsen.io/
- Jepsen consistency models — https://jepsen.io/consistency/models/sequential

### Testing tools

- bats-core — https://bats-core.readthedocs.io/ · https://github.com/bats-core
- cram — https://bitheap.org/cram/
- trycmd — https://docs.rs/trycmd
- insta — https://insta.rs/ · https://github.com/mitsuhiko/insta
- Hypothesis — https://hypothesis.readthedocs.io/
- Hypothesis quickstart — https://hypothesis.readthedocs.io/en/latest/quickstart.html
- proptest — https://docs.rs/proptest
- QuickCheck (Rust) — https://github.com/BurntSushi/quickcheck
- QuickCheck (Haskell) — https://hackage.haskell.org/package/QuickCheck
- fast-check — https://fast-check.dev/
- jqwik — https://jqwik.net/
- AFL++ — https://aflplus.plus/
- libFuzzer — https://llvm.org/docs/LibFuzzer.html
- cargo-fuzz — https://rust-fuzz.github.io/book/cargo-fuzz.html
- LibAFL paper — https://www.s3.eurecom.fr/docs/ccs22_fioraldi.pdf
- OSS-Fuzz — https://google.github.io/oss-fuzz/
- DIFFER (Trail of Bits) —
  https://blog.trailofbits.com/2024/01/31/introducing-differ-a-new-tool-for-testing-and-validating-transformed-programs/
- VCR.py — https://vcrpy.readthedocs.io/
- WireMock — https://wiremock.org/docs/
- mitmproxy — https://docs.mitmproxy.org/stable/
- GoReplay — https://goreplay.org/

### Idiomatic-language canon

- Effective Go — https://go.dev/doc/effective_go
- Go Code Review Comments — https://go.dev/wiki/CodeReviewComments
- Rust API Guidelines — https://rust-lang.github.io/api-guidelines/
- Rust Style Guide — https://doc.rust-lang.org/1.0.0/style/
- PEP 8 — https://peps.python.org/pep-0008/
- PEP 20 (Zen of Python) — https://peps.python.org/pep-0020/
- Google Python Style Guide — https://google.github.io/styleguide/pyguide.html
- Microsoft .NET Framework Design Guidelines —
  https://learn.microsoft.com/en-us/dotnet/standard/design-guidelines/
- Kotlin coding conventions — https://kotlinlang.org/docs/coding-conventions.html
- Google Java Style — https://google.github.io/styleguide/javaguide.html
- Google C++ Style Guide — https://google.github.io/styleguide/cppguide.html
- C++ Core Guidelines — https://github.com/isocpp/CppCoreGuidelines
- Scala Style Guide — https://docs.scala-lang.org/style/
- Google Shell Style Guide — https://google.github.io/styleguide/shellguide.html
- CLI Guidelines — https://clig.dev/
- Node.js best practices — https://github.com/goldbergyoni/nodebestpractices
- Writing CLI Tools That AI Agents Actually Want to Use —
  https://dev.to/uenyioha/writing-cli-tools-that-ai-agents-actually-want-to-use-39no

### Anti-patterns

- Second-system effect (Wikipedia) — https://en.wikipedia.org/wiki/Second-system_effect
- Avoiding Second System Syndrome in Code Rewrites —
  https://albrightlabs.com/blog/avoiding-second-system-syndrome-in-code-rewrites/
- Legacy Code and Chesterton's Fence — https://alexkondov.com/legacy-code-and-chestersons-fence/
- Chesterton's Fence and AI Removing Things It Doesn't Understand —
  https://fourweekmba.com/the-chestertons-fence-problem-ai-removing-things-it-doesnt-understand/
- Scope creep (Wikipedia) — https://en.wikipedia.org/wiki/Scope_creep
- Asana: Scope Creep in Project Management — https://asana.com/resources/what-is-scope-creep
- Writing Idiomatic Go: Patterns That Separate Clean Code From "Java in Go" —
  https://www.gocloudstudio.com/post/writing-idiomatic-go-patterns-that-separate-clean-code-from-java-in-go/

### LLM code translation research

- _Lost in Translation_ (ICSE 2024, IBM) — https://arxiv.org/abs/2308.03109
- IBM Research page —
  https://research.ibm.com/publications/lost-in-translation-a-study-of-bugs-introduced-by-large-language-models-while-translating-code
- Replication package — https://github.com/Intelligent-CAT-Lab/PLTranslationEmpirical
- ICSE 2024 proceedings —
  https://conf.researchr.org/details/icse-2024/icse-2024-research-track/226/Lost-in-Translation-A-Study-of-Bugs-Introduced-by-Large-Language-Models-while-Transl
- _Migrating Code At Scale With LLMs At Google_ — https://arxiv.org/abs/2504.09691
- ACM ESEC/FSE 2025 proceedings — https://dl.acm.org/doi/10.1145/3696630.3728542
- LinearB summary — https://linearb.io/blog/how-google-uses-ai-to-speed-up-code-migrations
- _LLM-Based Code Translation Needs Formal Compositional Reasoning_ (UC Berkeley, 2025) —
  https://www2.eecs.berkeley.edu/Pubs/TechRpts/2025/EECS-2025-174.pdf
- _Semantic Alignment-Enhanced Code Translation_ — https://arxiv.org/pdf/2409.19894
- _Scalable, Validated Code Translation of Entire Projects_ (Amazon) —
  https://assets.amazon.science/0e/ab/c10459dd4013a7c02f09b8c96f3f/scalable-validated-code-translation-of-entire-projects-using-large-language-models.pdf
- _Beyond Translation Accuracy_ — https://arxiv.org/abs/2605.02195
- TransCoder paper — https://arxiv.org/abs/2006.03511 · PDF: https://arxiv.org/pdf/2006.03511.pdf
- TransCoder repo — https://github.com/facebookresearch/TransCoder
- InfoQ on TransCoder — https://www.infoq.com/news/2020/06/facebook-ai-transpiler/
- SmellBench (architectural smells in LLM agents) — https://arxiv.org/html/2605.07001v1
- CodeBERT (Saturn Cloud glossary) — https://saturncloud.io/glossary/codebert/

### Agent skills, prompts, and customization

- Anthropic skills (official) — https://github.com/anthropics/skills
- Anthropic cookbooks — https://github.com/anthropics/claude-cookbooks
- Claude Code skills docs — https://code.claude.com/docs/en/skills
- Claude Code sub-agents — https://docs.anthropic.com/en/docs/claude-code/sub-agents
- Claude Code settings — https://docs.anthropic.com/en/docs/claude-code/settings
- Anthropic prompt-engineering best practices —
  https://docs.anthropic.com/en/docs/build-with-claude/prompt-engineering/claude-4-best-practices
- Anthropic prompt-eng interactive tutorial —
  https://github.com/anthropics/prompt-eng-interactive-tutorial
- Claude Code best practices — https://www.anthropic.com/engineering/claude-code-best-practices
- OpenAI Codex repo — https://github.com/openai/codex
- OpenAI `migrate-to-codex` SKILL.md —
  https://github.com/openai/skills/blob/main/skills/.curated/migrate-to-codex/SKILL.md
- OpenAI Codex prompting — https://developers.openai.com/codex/prompting
- OpenAI code generation guide — https://developers.openai.com/api/docs/guides/code-generation
- OpenAI prompt-engineering best practices —
  https://help.openai.com/en/articles/6654000-best-practices-for-prompt-engineering-with-the-openai-api
- Awesome Claude Code — https://github.com/jqueryscript/awesome-claude-code
- Awesome Claude Skills — https://github.com/travisvn/awesome-claude-skills ·
  https://awesomeclaudeskills.com/
- Awesome Cursor Rules — https://github.com/PatrickJS/awesome-cursorrules
- dotcursorrules — https://dotcursorrules.com/
- Cursor refactoring workshop — https://cursor.com/workshops/recording/refactoring-legacy-codebases
- Cline prompts — https://github.com/cline/prompts
- Cline rules guide — https://thepromptshelf.dev/blog/cline-rules-complete-guide-2026/
- Cline prompt engineering crash course —
  https://medium.com/@evanmusick.dev/cline-prompt-engineering-crash-course-custom-instructions-that-actually-work-520ef1162fc2/
- Aider — https://aider.chat/
- Aider migration case study — https://blog.netnerds.net/2024/10/aider-is-awesome/
- GitHub Copilot customization —
  https://docs.github.com/en/copilot/how-tos/copilot-on-github/customize-copilot/customize-copilot-overview
- GitHub Copilot custom instructions —
  https://docs.github.com/en/copilot/reference/custom-instructions-support
- Negative prompting (Emergent Mind) — https://www.emergentmind.com/topics/negative-prompting
- Case study on negative prompting for code review —
  https://trilogyai.substack.com/p/case-study-i-tested-the-negative

### Case studies (primary sources where possible)

- Discord Go → Rust — https://discord.com/blog/why-discord-is-switching-from-go-to-rust
- Discord Read States migration write-up (secondary) —
  https://medium.com/@chopra.kanta.73/why-discord-migrated-read-states-from-go-to-rust-bdff7fb7c487
- Cloudflare Pingora —
  https://blog.cloudflare.com/how-we-built-pingora-the-proxy-that-connects-cloudflare-to-the-internet
- Cloudflare ROFL — https://blog.cloudflare.com/rust-nginx-module
- Cloudflare FL2 — https://blog.cloudflare.com/it-it/20-percent-internet-upgrade/
- Cloudflare Workers how-it-works —
  https://developers.cloudflare.com/workers/reference/how-workers-works/
- Cloudflare Workers Rust SDK — https://blog.cloudflare.com/workers-rust-sdk/
- Cloudflare Workers Rust docs — https://developers.cloudflare.com/workers/languages/rust/
- Deno 2 — https://deno.com/blog/v2.0
- esbuild FAQ — https://esbuild.github.io/faq/
- swc — https://swc.rs/
- Astral — https://astral.sh/
- Ruff linter — https://docs.astral.sh/ruff/linter/
- Ruff rules — https://docs.astral.sh/ruff/rules/
- uv announcement — https://astral.sh/blog/uv-unified-python-packaging
- Astral story (Accel) —
  https://www.accel.com/noteworthies/astral-how-a-side-project-changed-python-tooling
- Biome announcement — https://biomejs.dev/blog/annoucing-biome/
- Oxc — https://oxc.rs/
- Bun docs — https://bun.com/docs
- Biome vs ESLint vs Oxlint 2026 — https://www.pkgpulse.com/guides/biome-vs-eslint-vs-oxlint-2026
- "Why Rust tooling is dominating JS in 2026" —
  https://dev.to/dataformathub/deep-dive-why-rust-based-tooling-is-dominating-javascript-in-2026-3dbl
- ripgrep FAQ — https://github.com/BurntSushi/ripgrep/blob/master/FAQ.md
- BurntSushi blog — https://burntsushi.net/
- ripgrep benchmarks — https://burntsushi.net/ripgrep/
- fd — https://github.com/sharkdp/fd · https://crates.io/crates/fd-find
- eza — https://eza.rocks/ · https://github.com/eza-community/eza
- bat — https://github.com/sharkdp/bat
- gitoxide — https://github.com/GitoxideLabs/gitoxide
- Gitoxide progress — https://medium.com/rustaceans/gitoxide-makes-strides-a60f95a9a398
- Mozilla Quantum CSS / Stylo —
  https://hacks.mozilla.org/2017/08/inside-a-super-fast-css-engine-quantum-css-aka-stylo/
- servo/stylo — https://github.com/servo/stylo
- HN: Stylo in Firefox — https://news.ycombinator.com/item?id=15799310
- Dropbox Magic Pocket (primary) — https://dropbox.tech/tech/2016/05/inside-the-magic-pocket/
- Dropbox Magic Pocket cold-storage —
  https://dropbox.tech/infrastructure/how-we-optimized-magic-pocket-for-cold-storage
- QCon SF 2016 — Going to Rust at Dropbox —
  https://qconsf.com/sf2016/sf2016/presentation/going-rust-optimizing-storage-dropbox.html
- "Rewritten in Rust: Modern Alternatives of Command-Line Tools" —
  https://zaiste.net/posts/shell-commands-rust/

### Decision capture

- Nygard, Documenting Architecture Decisions —
  https://www.cognitect.com/blog/2011/11/15/documenting-architecture-decisions
- adr.github.io — https://adr.github.io/
- MADR — https://adr.github.io/madr/
- adr-tools — https://github.com/npryce/adr-tools
- Henderson's ADR collection — https://github.com/joelparkerhenderson/architecture-decision-record

---

## 16. Quick-Start Checklist (For Pasting Into a New Project)

```
[ ] Phase A — Contract Extraction
    [ ] contract/cli-surface.md
    [ ] contract/exit-codes.md
    [ ] contract/stdout-stderr-shape.md
    [ ] contract/help-text/*.golden
    [ ] contract/openapi.yaml (if applicable)
    [ ] contract/error-payloads.md (if applicable)
    [ ] contract/on-disk-formats.md / wire-formats.md (if applicable)
    [ ] contract/config-schema.json
    [ ] contract/semver-promises.md
    [ ] contract/parity-boundary.md
    [ ] adr/0001-rewrite-decision.md
    [ ] adr/0002-parity-boundary.md

[ ] Phase B — Freeze Behavior
    [ ] parity-tests/golden/ — passes against SOURCE
    [ ] parity-tests/replay/ — passes against SOURCE (if service)
    [ ] parity-tests/characterization/ — passes against SOURCE
    [ ] parity-tests/property/ — passes against SOURCE
    [ ] parity-tests/perf/ — baseline recorded
    [ ] Coverage report mapping contract → parity tests

[ ] Phase C — Idiomatic Design
    [ ] design/architecture.md
    [ ] design/dependencies.md
    [ ] design/error-model.md
    [ ] design/concurrency-model.md
    [ ] adr/0003-*, 0004-*, ... for non-trivial choices
    [ ] Phase C performed WITHOUT reading source code

[ ] Phase D — Implementation
    [ ] Anti-transliteration guardrails active
    [ ] Each implemented feature ships with its parity test
    [ ] Translation-smell review pass on each change

[ ] Phase E — Verification
    [ ] All Phase-B parity tests pass against TARGET
    [ ] Property tests pass against TARGET
    [ ] Differential tests against source — clean
    [ ] Fuzz campaign — no crashes, no divergences
    [ ] Shadow traffic — divergences resolved or ADR'd
    [ ] Performance baseline within documented envelope

[ ] Phase F — Cutover
    [ ] Parallel-run period complete
    [ ] Canary 1–5% — clean
    [ ] Progressive rollout 5% → 25% → 50% → 100%
    [ ] Rollback procedure tested at each step
    [ ] Decommission of source after confidence period
    [ ] adr/9999-postmortem.md
```

---

## 17. Companion Documents

- `tech/programming/cli-design/` — CLI design reference (relevant when the target system is a CLI)
- `tech/programming/best-practices/operational-responsibilities.md` — operational checklist for the
  post-rewrite system
- `tech/workflows/bash-program-release-workflow.md` — distribution for Bash-target rewrites
- `tech/data/dbs-databases/migrations.md` — DB-schema migration (a data-side counterpart to this
  code-side guideline)

---

> **End of guideline.** This document is the spec. When loaded as a prompt or skill, the agent must
> treat [§0 non-negotiables](#0-non-negotiables-read-this-section-first), the
> [§3 phase model](#3-mandatory-phase-model), and the
> [§6 refusal list](#6-refusal-list-translation-smells-to-reject) as binding rules, not advisory
> guidance.
