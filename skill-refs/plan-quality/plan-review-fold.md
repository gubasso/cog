# Plan Review Fold Protocol

An annotated plan review remains a review. It is an audit delta against a base plan, not an implementation plan. The plan-naming consumer owns the semantic fold: read the validated base plan and validated review together, then author a complete replacement plan that stands on its own.

For target `<stem>.md`, retain `<stem>-review.md`, `<stem>-review-items.json`, `<stem>-fold-manifest.json`, and `<stem>-fold-check.json` beside it. Use this ordered protocol and stop on any failed command:

1. Validate the base plan with `cog plan-doc validate <base-abs.md>`.
2. Validate the review with `cog plan-review validate <review-abs.md>`.
3. Save `cog plan-review items <review-abs.md> --json` as `<stem>-review-items.json`.
4. Create the target with `cog plan-doc save --title <title> --repo-root <repo-abs> --output <stem>.md`, then fill every section with one coherent, self-contained implementation plan. Retain APPROVED material, substitute MODIFIED material, omit REMOVED material, and integrate ADDED material.
5. Write `<stem>-fold-manifest.json` with schema `cog.plan-review.fold-manifest.v1` and exactly one disposition for every derived item ID. `folded` means the annotation's required effect is represented in the final plan, including the intentional absence of REMOVED material. `waived` is reserved for a consciously rejected annotation and requires a concrete, non-blank `reason`. A folded item may include a `note`.
6. Run `cog plan-doc validate <stem>.md`.
7. Save `cog plan-review fold-check --review <review-abs.md> --plan <stem>.md --manifest <stem>-fold-manifest.json --json` as `<stem>-fold-check.json` and require `ok: true`.

The manifest records semantic judgment. `fold-check` proves deterministic item coverage only; it does not claim that the prose fold is semantically correct. The receipt contains the current review, plan, and manifest SHA-256 values and must remain beside the artifacts. A receipt is current only when all three hashes still match the files it names, so any later edit to the review, the plan, or the manifest requires rerunning both `cog plan-doc validate` and `fold-check`; update the manifest first when a disposition changes.

The implementation worker receives only the folded plan. The base plan, annotated review, item listing, manifest, and receipt remain separate audit artifacts and are never inlined as the authoritative implementation plan.
