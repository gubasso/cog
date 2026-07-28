# Primary-source verification

Single source of truth for the primary-source verification directive. Consumed by the review, implementation-review, review-plan, and test-review skill families (resolved in their own context via `cog skill-refs path research/primary-source-verification.md`) and injected into the `ask -w` research sub-prompt. Each consuming skill keeps its own role-specific wiring (research targets, phases, examples); this file owns the canonical directive.

## Directive

Verify every claim about an external API, library, tool, language, or spec against primary, official sources — official docs, language specs, RFCs, man pages, changelogs, and upstream repositories. Do not rely on training data for API signatures, config options, or library behavior: search and verify. Blog posts and Q&A sites may corroborate a primary source but never establish a fact on their own. Prefer version-specific sources when the project pins or implies a version, and check for deprecations, breaking changes, and migration notes. Cite the exact source URL for each verified claim, and mark anything you cannot verify as unverified rather than asserting confidence.
