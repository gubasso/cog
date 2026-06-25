# ADR-0033: Benchmark Source Tiers

## Context and Problem Statement

ADR-0032 makes `power-grade-matrix.toml` the profile SoT with `needs_verification` evidence markers
for public-data gaps, but it does not say which sources are trustworthy enough to clear such a gap.
In practice the model-reference docs cited a mix of vendor pages and unaudited aggregators
(`vellum`, `llm-stats`, `morphllm`, `marc0.dev`, `danielvaughan`), and there was no single place
declaring source trust. That makes "is this number sourced well enough?" an ad-hoc judgment and lets
a weak aggregator silently back a grade.

## Considered Options

- Forbid aggregators and allow only vendor pages.
- Tier sources by methodology transparency and record the tiering in one machine-readable SoT.
- Keep tiering implicit in each model-reference doc's PRIMARY/SECONDARY labels.

## Decision Outcome

Chosen option: **Tier sources by methodology transparency in one machine-readable SoT.** The axis is
reproducibility and provenance, not vendor-vs-third-party: a benchmark owner's public leaderboard is
as authoritative as a vendor page, a vendor mirror can clear when it restates first-party benchmark
numbers in readable text, and a copy-paste aggregator is not.

`docs/reference/power-grade-source-allowlist.toml` is the SoT. Each `[[sources]]` entry carries a
`tier`, what it is `trusted_for` / `not_trusted_for`, methodology transparency, and a
`clears_needs_verification` flag:

- **Tier 1 (canonical or first-party restatement):** vendor docs for model facts (pricing, context,
  cutoff, effort support); benchmark owners for their own scores; vendor mirrors that restate
  first-party benchmark numbers in readable text. Clears a cell.
- **Tier 2 (secondary):** an independent aggregator transparent enough to trace to upstream
  methodology, or reputable secondary press when a revalidation artifact confirms the figure and no
  Tier 1 numeric source is available. Clears a cell only with a recorded caveat.
- **Tier 3 (weak/excluded):** no published methodology, copies upstream, marketing, or link-rot.
  Never clears a cell; recorded so a forbidden source is not silently re-introduced.

A source's tier can differ by data type (e.g. Artificial Analysis is Tier 1 for its own measured
price/latency, Tier 2 for aggregated benchmarks), captured in `trusted_for` / `not_trusted_for`.

Worked examples:

- Opus 4.7 can clear from the AWS Bedrock launch post because it is an official vendor mirror that
  restates Anthropic's scores in readable text: SWE-bench Verified 87.6%, SWE-bench Pro 64.3%, and
  Terminal-Bench 2.0 69.4%. Vals AI remains Tier 2 corroboration for its own SWE-bench Verified
  harness, which reads 82.0%.
- gpt-5.4-mini can clear only with a caveat: OpenAI provides a Tier 1 qualitative statement that it
  approaches gpt-5.4 on SWE-bench Pro, while the numeric 54.38% SWE-bench Pro figure comes from
  Tier 2 secondary press. SWE-bench Pro and SWE-bench Verified are distinct benchmarks and must not be
  compared as the same measure.

ADR-0033 references ADR-0032 and ADR-0013 and supersedes neither: it adds the sourcing policy that
governs when a matrix cell's `evidence_status` may move off `needs_verification`.

## Consequences

- Good: "well-sourced enough?" becomes a tier lookup against one reviewable file.
- Good: excluded aggregators are recorded once, so they are not re-added to model-reference docs.
- Good: numeric benchmark figures are cleared only from Tier 1 sources or Tier 2 with a caveat; gaps
  with no qualifying source honestly stay `needs_verification`.
- Bad: the allowlist itself perishes (URLs move, leaderboards change) and needs periodic
  revalidation; it is registered in `maintenance-tracking.yaml`.

## Status

Implemented by `docs/reference/power-grade-source-allowlist.toml`, registered in
`docs/reference/maintenance-tracking.yaml`. The model-reference docs cite only Tier 1/2 sources.
