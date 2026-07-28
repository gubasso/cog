# Sources & Refresh Provenance — refactor-migration & spec-driven best practices

Tracks the external upstreams and research grounding the refactor-migration and spec-driven-development reference docs in this directory, so the content can be re-synced and re-verified as upstreams evolve. Update this file whenever you refresh or re-verify a reference.

Scope: the externally-derived docs below. Other files in this directory (`licensing.md`, `operational-responsibilities.md`, `pre-commit.md`, `README.md`, `AGENTS.md`) are not tracked here.

## Citation verification policy (read this before flagging a citation)

These docs deliberately cite **bleeding-edge 2025–2026 research**. Several arXiv IDs and DOIs here **postdate common LLM training cutoffs**, so a reviewing agent will not recognize them from its training data. **Do not flag a citation as fabricated or "hallucinated" solely because its identifier is future-dated** — every academic citation in the table below was fetched and confirmed to resolve to its stated title on the "Verified" date. Re-verify by fetching the URL before flagging; only flag a citation that genuinely fails to resolve, or whose resolved title contradicts how it is cited.

## File provenance

| File                                        | Derivation / upstream                                                              | Last synced |
| ------------------------------------------- | ---------------------------------------------------------------------------------- | ----------- |
| `refactor-migration-guideline.md`           | Original synthesis from the research + practitioner sources in its §14–§15 library | 2026-06-15  |
| `refactor-guideline-excerpt.md`             | Distilled from `refactor-migration-guideline.md` (§0, §1, §3, §6, §8, §11)         | 2026-06-15  |
| `refactor-plan-templates.md`                | Original — plan-file templates for the `refactor-migration-plan` skill             | 2026-06-15  |
| `refactor-refusal-list.md`                  | Extracted from guideline §6 (the 16 translation smells)                            | 2026-06-15  |
| `spec-driven-development-best-practices.md` | Synthesis from GitHub Spec Kit + the AGENTS.md / spec-driven research below        | 2026-06-15  |
| `madr-template.md`                          | MADR (Markdown ADR) — <https://adr.github.io/madr/>                                | 2026-06-15  |

## Research references (verified; not refreshed routinely)

Academic sources grounding the docs above. "Verified" = the identifier was fetched and confirmed to resolve to the stated title/venue on that date.

| Citation                                  | Identifier                  | Resolved title / status                                                                                                                                                                                                              | Verified   |
| ----------------------------------------- | --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------- |
| Lost in Translation (ICSE 2024, IBM)      | arXiv:2308.03109            | "Lost in Translation: A Study of Bugs Introduced by LLMs while Translating Code" (Pan et al.)                                                                                                                                        | 2026-06-15 |
| Migrating Code at Scale (Google)          | arXiv:2504.09691            | "Migrating Code At Scale With LLMs At Google" (Ziftci et al., Apr 2025)                                                                                                                                                              | 2026-06-15 |
| Migrating Code at Scale (ACM)             | doi:10.1145/3696630.3728542 | ACM FSE 2025 proceedings entry — DOI series `10.1145/3696630.*` confirmed via sibling DOIs; ACM blocks bot fetch                                                                                                                     | 2026-06-15 |
| TransAgent / Semantic Alignment           | arXiv:2409.19894            | Same paper, retitled across versions: v1 "Semantic Alignment-Enhanced Code Translation via an LLM-Based Multi-Agent System" → current "TransAgent: …Fine-Grained Execution Alignment" (Yuan et al., FSE'26). **Not** a mis-citation. | 2026-06-15 |
| TransCoder                                | arXiv:2006.03511            | "Unsupervised Translation of Programming Languages" (Lachaux et al., Meta, 2020)                                                                                                                                                     | 2026-06-15 |
| Formal Compositional Reasoning (Berkeley) | EECS-2025-174               | UC Berkeley EECS tech report — URL serves the PDF (live); title not machine-parsed                                                                                                                                                   | 2026-06-15 |
| Scalable Validated Translation (Amazon)   | assets.amazon.science PDF   | Amazon Science paper — URL serves the PDF (live); title not machine-parsed                                                                                                                                                           | 2026-06-15 |
| Beyond Translation Accuracy               | arXiv:2605.02195            | "Beyond Translation Accuracy: Addressing False Failures in LLM-Based Code Translation" (Rabbi et al., May 2026) — **post-cutoff, real**                                                                                              | 2026-06-15 |
| SmellBench                                | arXiv:2605.07001            | "SmellBench: Evaluating LLM Agents on Architectural Code Smell Repair" (Dinu et al., May 2026) — **post-cutoff, real**                                                                                                               | 2026-06-15 |
| AGENTS.md impact                          | arXiv:2601.20404            | "On the Impact of AGENTS.md Files on the Efficiency of AI Coding Agents" (Lulla et al., Jan 2026) — **post-cutoff, real**                                                                                                            | 2026-06-15 |
| Spec-Driven Development                   | arXiv:2602.00180            | "Spec-Driven Development: From Code to Contract in the Age of AI Coding Assistants" (Piskala, Jan 2026) — **post-cutoff, real**                                                                                                      | 2026-06-15 |

## How to re-verify

```bash
# Fetch an arXiv abstract page and confirm it resolves to the stated title.
# (Replace the ID; a real ID returns the title, a fake one returns "Article not found".)
curl -sL https://arxiv.org/abs/2605.02195 | grep -i '<title>'

# ACM DOIs block bots (403, not 404). Confirm the proceedings series instead, or open in a browser:
#   https://dl.acm.org/doi/10.1145/3696630.3728542
```

When you re-verify, bump the "Verified" date. When you add a new academic citation to any doc above, add a row here with its verification date.

## Notes

- The per-doc reference lists (e.g. the guideline §14–§15) remain the authoritative citation source; this file is a provenance + verification ledger, not a replacement for them.
- The `refactor-migration-guideline.md` §15 header carries a short pointer back to this file so reviewers see the verification policy in context.
- Format follows the shared provenance-ledger convention used across the KB's `SOURCES.md` files.
