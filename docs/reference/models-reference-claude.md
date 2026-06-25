# Claude Models Reference

A dated reference for Claude model pricing, limits, effort support, benchmarks, and caveats used by
`cog` model/effort policy.

Data collected: 2026-06-19; re-verified 2026-06-25 (Haiku SWE-bench, Opus 4.7 cutoff and benchmark restatement, source tiers)

Revalidate by: 2026-09-25, or sooner on any new model release or pricing change

Sources (trust tiers and the full allowlist live in
[`power-grade-source-allowlist.toml`](power-grade-source-allowlist.toml)):

- PRIMARY: <https://platform.claude.com/docs/en/about-claude/models/overview>
- PRIMARY: <https://platform.claude.com/docs/en/about-claude/pricing>
- PRIMARY: <https://platform.claude.com/docs/en/about-claude/models/migration-guide>
- PRIMARY: <https://platform.claude.com/docs/en/build-with-claude/effort>
- PRIMARY: <https://www.anthropic.com/news/claude-opus-4-8>
- PRIMARY: <https://www.anthropic.com/news/claude-haiku-4-5>
- PRIMARY: <https://www.anthropic.com/news/claude-sonnet-4-6>
- PRIMARY: <https://www.anthropic.com/transparency> (system/model card index)
- PRIMARY: Opus 4.8 System Card, 2026-05-28:
  <https://www-cdn.anthropic.com/0b4915911bb0d19eca5b5ee635c80fef830a37ea/Claude%20Opus%204.8%20System%20Card.pdf>
- TIER-1 VENDOR MIRROR: <https://aws.amazon.com/blogs/aws/introducing-anthropics-claude-opus-4-7-model-in-amazon-bedrock/>
- BENCHMARK-OWNER: <https://www.swebench.com/verified.html> (SWE-bench Verified leaderboard)
- TIER-2 CORROBORATION: <https://www.vals.ai/benchmarks/swebench> (Vals AI SWE-bench Verified harness)

Numeric benchmark figures are cleared from PRIMARY vendor pages, benchmark-owner leaderboards, or
Tier-1 vendor mirrors that restate first-party numbers in readable text. Tier 2 sources are cited only
with a caveat; Tier 3 sources are not cited here (see the allowlist).

## Model Catalog

| Model | ID | Context / max output | Input / cache-read / output $ per MTok | Cache-write / batch pricing | Effort levels | Headline benchmark | Knowledge cutoff | Confidence |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Opus 4.8 | `claude-opus-4-8` | 1M / 128K; up to 300K output via `output-300k` beta on Batch | $5 / $0.50 / $25 | 5-min write $6.25; 1-hour write $10; Batch $2.50 input / $12.50 output | `low`, `medium`, `high`, `xhigh`, `max`; default `high` | SWE-bench Verified about 88.6% (SECONDARY); Online-Mind2Web 84% (MEDIUM/PRIMARY) | reliable Jan 2026; training Jan 2026 | HIGH/PRIMARY (Anthropic pricing/overview/effort pages, fetched 2026-06-19) for pricing, limits, effort, cutoff; benchmark as tagged |
| Opus 4.7 (previous-generation Opus, current active model) | `claude-opus-4-7` | 1M / 128K | $5 / $0.50 / $25 | 5-min write $6.25; 1-hour write $10; Batch $2.50 input / $12.50 output | `low`, `medium`, `high`, `xhigh`, `max`; default `high` | SWE-bench Verified 87.6%, SWE-bench Pro 64.3%, Terminal-Bench 2.0 69.4% (Tier-1 vendor mirror); Vals AI reads 82.0% SWE-bench Verified under its independent harness (Tier-2 corroboration) | reliable Jan 2026; training Jan 2026 (PRIMARY, models overview legacy table) | Pricing/limits/effort corroborated by in-repo `claude-api` catalog (IDs, context/output) plus Anthropic pricing page; cutoff Jan 2026 (PRIMARY, models overview); benchmark sourced via AWS Bedrock vendor mirror because Anthropic's own page is chart-only |
| Sonnet 4.6 | `claude-sonnet-4-6` | 1M / 64K | $3 / $0.30 / $15 | 5-min write $3.75; 1-hour write $6; Batch $1.50 input / $7.50 output | `low`, `medium`, `high`, `max`; no `xhigh`; default `high` | SWE-bench Verified 79.6%; Multilingual SWE-bench 75.9% (MEDIUM/PRIMARY) | reliable Aug 2025; training Jan 2026 | HIGH/PRIMARY (Anthropic pricing/overview/effort pages, fetched 2026-06-19) for pricing, limits, effort, cutoff; benchmark MEDIUM/PRIMARY |
| Haiku 4.5 | `claude-haiku-4-5` (full: `claude-haiku-4-5-20251001`) | 200K / 64K | $1 / $0.10 / $5 | 5-min write $1.25; 1-hour write $2; Batch $0.50 input / $2.50 output | `effort` returns an error; unsupported | SWE-bench Verified 73.3% (PRIMARY, Anthropic news, 2026-06-24) | reliable Feb 2025; training Jul 2025 | HIGH/PRIMARY (Anthropic pricing/overview/effort pages, fetched 2026-06-19); benchmark PRIMARY (Anthropic news) |

## Claude Effort Semantics

The per-model effort specifics below (which levels each model supports, defaults, the Sonnet
"no `xhigh`" differentiator, and the Haiku "effort returns an error" behavior) come from the
Anthropic effort documentation page (`build-with-claude/effort`, in Sources), fetched 2026-06-19,
not from the in-repo `claude-api` catalog, which records only a generic effort capability tree.

Opus 4.8 supports `low`, `medium`, `high`, `xhigh`, and `max`, with default `high`. For Opus 4.8,
default to `high` and sweep effort by route; use `xhigh` for coding or agentic work that needs more
reasoning, and reserve `max` for the hardest tasks.

Opus 4.7 supports the same effort levels as Opus 4.8. It is a previous-generation Opus model, and
`xhigh` is the Claude Code default for that generation.

Sonnet 4.6 supports `low`, `medium`, `high`, and `max`, with default `high`. It does not support
`xhigh`; this is a real differentiator from Opus 4.8. Anthropic documentation recommends
setting Sonnet 4.6 to `medium` when latency matters.

Haiku 4.5 does not support selectable effort. Sending the `effort` parameter returns an error, so
`cog` policy and skills must omit it for Haiku.

## Power Grade Inputs

This section is the dated Claude evidence row set consumed by
`docs/reference/power-grade-matrix.toml`. It consolidates existing sourced facts from this reference;
it does not add newly researched benchmark numbers.

| Source row id | Model | Effort axis for matrix | Coding benchmark input | Cost input | Effort-quality input | Effort-cost input | Power Grade caveats |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `claude:opus-4.8` | Opus 4.8 (`claude-opus-4-8`) | `low`, `medium`, `high`, `xhigh`, `max`; default `high` | SWE-bench Verified about 88.6% (SECONDARY); Online-Mind2Web 84% (MEDIUM/PRIMARY) | $5 input / $0.50 cache read / $25 output per MTok; cache-write and batch prices in Model Catalog | Anthropic effort docs support tiered reasoning; default `high`; use `xhigh` for coding or agentic work that needs more reasoning; reserve `max` for hardest tasks | Published exact per-effort token multipliers are not asserted in this Claude reference; cost increases directionally with more thinking/output | SWE-bench figure is SECONDARY; effort deltas are qualitative, not numeric |
| `claude:opus-4.7` | Opus 4.7 (`claude-opus-4-7`) | `low`, `medium`, `high`, `xhigh`, `max`; default `high` | SWE-bench Verified 87.6%, SWE-bench Pro 64.3%, Terminal-Bench 2.0 69.4% (Tier-1 vendor mirror); Vals AI reads 82.0% SWE-bench Verified under its independent harness (Tier-2 corroboration) | $5 input / $0.50 cache read / $25 output per MTok; cache-write and batch prices in Model Catalog | Same supported effort set as Opus 4.8; `xhigh` is the Claude Code default for that generation | Published exact per-effort token multipliers are not asserted in this Claude reference | Anthropic's own page is chart-only for these benchmark numbers; AWS Bedrock carries the readable first-party restatement; cutoff Jan 2026 (PRIMARY, models overview); do not infer Opus 4.8 benchmark numbers for this row |
| `claude:haiku-4.5` | Haiku 4.5 (`claude-haiku-4-5`) | no selectable effort; matrix uses a single `none` cell | SWE-bench Verified 73.3% (PRIMARY, Anthropic news, 2026-06-24) | $1 input / $0.10 cache read / $5 output per MTok; cache-write and batch prices in Model Catalog | `effort` is unsupported and returns an error; there is no effort-quality axis | There is no effort-cost axis because effort must be omitted | Coding benchmark sourced (SWE-bench Verified 73.3%, PRIMARY); unsupported efforts must not be emitted as executable cells |

### Claude model-effort qualitative inputs

| Source row id | Effort | Qualitative Power Grade input |
| --- | --- | --- |
| `claude:opus-4.8:low` | `low` | Strong model at reduced effort; use for bounded procedural work when Opus quality is desired and the task is already structured. |
| `claude:opus-4.8:medium` | `medium` | Middle reasoning budget for moderately complex execution; no published numeric delta from low/high is asserted here. |
| `claude:opus-4.8:high` | `high` | Default exploration/planning effort; strongest regular policy pairing before escalation. |
| `claude:opus-4.8:xhigh` | `xhigh` | Escalation for coding or agentic work that needs more reasoning. |
| `claude:opus-4.8:max` | `max` | Highest effort tier; reserve for hardest tasks because cost/latency increase directionally with more thinking/output. |
| `claude:opus-4.7:low` | `low` | Previous-generation Opus at reduced effort; benchmark evidence is sourced via AWS Bedrock vendor mirror with Vals AI corroboration. |
| `claude:opus-4.7:medium` | `medium` | Previous-generation middle effort; benchmark evidence is sourced via AWS Bedrock vendor mirror with Vals AI corroboration. |
| `claude:opus-4.7:high` | `high` | Previous-generation regular high effort; benchmark evidence is sourced via AWS Bedrock vendor mirror with Vals AI corroboration. |
| `claude:opus-4.7:xhigh` | `xhigh` | Previous-generation Claude Code default; benchmark evidence is sourced via AWS Bedrock vendor mirror with Vals AI corroboration. |
| `claude:opus-4.7:max` | `max` | Highest previous-generation effort; benchmark evidence is sourced via AWS Bedrock vendor mirror with Vals AI corroboration. |
| `claude:haiku-4.5:none` | `none` | Single executable Haiku cell; effort must be omitted. |

## Policy-Forward Note

`sonnet` is never selected by `cog` policy. Sonnet 4.6 appears in this reference only for comparison
and for documenting why policy rounds choose Opus at lower effort instead of Sonnet.

## Cross-Model Caveats

Prompt caching multipliers are uniform across these models: 5-minute cache writes cost 1.25x input,
1-hour cache writes cost 2x input, and cache reads cost 0.1x input. Batch API pricing is a flat 50%
discount on input and output.

Tokenizer behavior matters for effective cost. Opus 4.7 and Opus 4.8 share the tokenizer introduced
with Opus 4.7, so token counts are roughly unchanged between them. Moving from Opus 4.6, Sonnet,
Haiku, or older models to this tokenizer can increase effective token count by about 1x to 1.35x, up
to roughly 35%. This is not a 4.8-vs-4.7 inflation.

The `inference_geo: "us"` 1.1x multiplier is left out of the main pricing table because it is not
confirmable from the in-repo catalog. Treat it as NEEDS VERIFICATION unless reconfirmed from a
current Anthropic pricing source.

## Evidence for Opus Low Instead of Sonnet

Opus 4.8 costs about 1.67x Sonnet 4.6 per token: $5 vs $3 per MTok input and $25 vs $15 per MTok
output. Cost parity against Sonnet therefore depends on Opus at lower effort emitting substantially
fewer output and thinking tokens. That is a directional policy argument, not a guaranteed equality.

The strongest official precedent is from the Opus 4.5 and Sonnet 4.5 generation: Opus 4.5 at medium
effort matched Sonnet 4.5's best SWE-bench Verified result while using substantially fewer output
tokens. Treat that precedent as directional for current models, not as a precise Opus 4.8 claim.

The quality delta remains policy-relevant: Opus 4.8's SWE-bench Verified figure is about 88.6%
(SECONDARY), while Sonnet 4.6 is 79.6% (MEDIUM/PRIMARY). Even when effort is reduced, Opus is the
higher-capability model.

## Confidence and Uncertainty

Pricing, context, output limits, and effort support are HIGH/PRIMARY or HIGH/PRIMARY-equivalent
where backed by official Anthropic sources and the in-repo `claude-api` model catalog.

Opus SWE-bench figures are SECONDARY where the official result is only available as a chart or
through benchmark aggregators rather than machine-readable official text.
