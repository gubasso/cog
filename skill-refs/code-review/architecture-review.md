# Architecture Review

Load this guide when the diff crosses module/package boundaries, introduces a new layer, or changes
how existing components communicate. For pure single-file changes, `process.md` and
`code-quality-universal.md` are usually enough.

## Trigger heuristics

Open this file when the diff has any of:

- New top-level directory or module.
- New interface/trait/protocol with ≥2 implementations.
- A file moves across `domain`/`application`/`adapter`/`presentation` layers.
- Database schema change, new external system integration, or new public API.
- Refactor labeled "extract", "split", "merge", or "decouple".

## The headline questions

For every architectural change, answer:

1. **What boundary is this change actually drawing?** Identify the contract — inputs, outputs, error
   modes, lifecycle. Vague boundaries beget leaky abstractions.
2. **Who owns the new component?** If two teams/modules both write to it, ownership is undefined and
   you get drift.
3. **What's on the other side of the boundary that didn't exist before?** A new layer adds a place
   where bugs can hide.
4. **What is the rollback path?** If the new shape is wrong, how do we get back?

## SOLID, briefly

Use these as smell-detectors, not as commandments.

| Principle | Smell to look for in the diff                                                                                               |
| --------- | --------------------------------------------------------------------------------------------------------------------------- |
| **S**RP   | A class/module touches >2 axes of change (data + transport + presentation, say). Split.                                     |
| **O**CP   | New feature forced a modification deep inside existing code instead of an extension point. Look for missing pluggability.   |
| **L**SP   | Subtype overrides throw or no-op on operations the supertype documents. Often indicates inheritance where composition fits. |
| **I**SP   | Interface forces implementations to provide unused methods. Split into focused interfaces.                                  |
| **D**IP   | High-level module imports a low-level concrete type. Invert via interface in the domain layer.                              |

## Coupling and cohesion

- **High cohesion**: a module's parts all serve one purpose. Smell: file holds three unrelated
  structs/classes with no shared behavior.
- **Low coupling**: a module talks to few neighbors via narrow interfaces. Smell: a "utils" or
  "helpers" module that 30 other files import.

Concrete review heuristic: count unique imports per file. If a file imports >15 distinct local
modules, it's a god-module candidate.

## Layering rules

Layers should depend inward — Presentation → Application → Domain — never outward.

Common violations:

- Domain types implementing transport interfaces (e.g., a domain `User` derives JSON serialization).
  Use a DTO at the boundary instead.
- Database models leaked to handlers/controllers. Map at the edge.
- Direct `print`/`stdout` calls from domain code. Pass a UI handle in, never call out.

In a CLI per the local canon (`cog skill-refs path cli-design/00-architecture.md`), layers map: `cli/`+`ui/`
(Presentation) → `commands/`+`services/` (Application) → `domain/` (Domain), with
`adapters/`+`config/`+`context.rs` as Infrastructure.

## Common architectural anti-patterns

### God object / god module

One class or file that does most of the work. Symptoms: >500 lines, >20 public methods, imported by
half the codebase. Refactor by responsibility.

### Anemic domain model

Domain types are pure data with all behavior living in "service" classes. Often a sign the domain
isn't earning its keep — fold the simple methods back into the types.

### Service explosion

`UserService`, `UserManager`, `UserHelper`, `UserUtil`, `UserOrchestrator`. When you have suffix
proliferation, the boundary is unclear. Consolidate or rename to verb-based modules.

### Generic-name dumping ground

`utils`, `common`, `shared`, `core`, `helpers` directories that hold unrelated code. Pull each
helper to a domain-named home; if you can't name it, it's probably leaking abstraction.

### Premature abstraction

Single-implementation interface + factory + provider for a feature that has one consumer. Wait for
the second consumer before extracting; the first abstraction is almost always wrong.

### Cross-cutting via decoration in every command

Logging, auth, telemetry copy-pasted into every handler. Lift into middleware or a wrapper at the
dispatch boundary. (Per local canon: middleware lives in `adapters/` until it grows past ~300 LOC.)

## Public API changes

Any change to a public interface (library API, HTTP route, CLI flag, database column visible to
consumers) carries amplified review weight:

1. **Backward compatibility.** Is this additive or breaking? Breaking changes need a deprecation
   path and a migration note.
2. **Versioning policy.** Does the project follow SemVer / CalVer / something else? Does this change
   require a major bump?
3. **Documentation.** README, OpenAPI spec, CHANGELOG, `--help` text all updated in the same PR.
4. **Telemetry.** If the API is observable in production, are the new fields/operations logged with
   stable identifiers?

## CLI architecture (when `--cli` is active)

See `cog skill-refs path cli-design/00-architecture.md` for the parse-shape vs runtime-shape
discipline, the four-edit rule for subcommands, and the single-`AppContext` rule. Common review-time
flags:

- Handler taking `Args` by value AND calling `Args::run()` — couples parse-shape to runtime.
- Per-command async runtime construction — should be one runtime in `main`, threaded via context.
- `Box<dyn Command>` registry / plugin trait — explicit dispatch is almost always better.

## Reuse and extraction

Before accepting a new layer/module, audit:

1. Does an existing module cover this? See [code-quality-universal.md](code-quality-universal.md)
   reuse audit.
2. Is there a third-party library that does this competently? Adding code is a liability; pulling a
   battle-tested dep is often cheaper.
3. If extracting, is the call graph clean? Service-as-passthrough (a service that just calls one
   adapter) is dead weight.

## Decision recording

For non-trivial architectural changes, the PR should reference (or include) a brief decision record:
problem statement, options considered, chosen option, trade-offs. The `refactor-migration-plan`
skill emits a MADR-format record; use that template if you have nothing else.

## See also

- [process.md](process.md), [code-quality-universal.md](code-quality-universal.md) — base review
  workflow.
- [performance-review.md](performance-review.md) — when the architectural change has performance
  implications.
- `cog skill-refs path cli-design/AGENTS.md` — CLI-specific structural rules.
- `$(cog skill-refs path cli-design/00-architecture.md)` — reference for CLI architecture vocabulary
  used here.
