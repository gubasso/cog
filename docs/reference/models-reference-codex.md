# Codex / GPT Models Reference

A dated reference for Codex-selectable GPT model pricing, effort support, benchmarks, and
subscription availability used by `cog`.

Data collected: 2026-06-19

Revalidate by: 2026-09-19, or sooner on any new model release, CLI availability change, or pricing
change

Sources:

- PRIMARY: <https://developers.openai.com/api/docs/models/gpt-5.5>
- PRIMARY: <https://developers.openai.com/api/docs/models/gpt-5.4>
- PRIMARY: <https://developers.openai.com/api/docs/models/gpt-5.4-mini>
- PRIMARY: <https://developers.openai.com/codex/pricing>
- PRIMARY: <https://developers.openai.com/api/docs/guides/latest-model>
- PRIMARY: <https://developers.openai.com/codex/changelog>
- PRIMARY: <https://github.com/openai/codex>
- PRIMARY: <https://github.com/openai/codex/issues/19654>
- PRIMARY: <https://github.com/openai/codex/issues/14306>
- PRIMARY: <https://github.com/openai/codex/issues/26116>
- SECONDARY: <https://codex.danielvaughan.com/2026/03/27/reasoning-effort-tuning/>
- SECONDARY: <https://www.marc0.dev/en/leaderboard>
- SECONDARY: <https://llm-stats.com>
- SECONDARY: <https://www.morphllm.com/swe-bench-pro>

## Model Catalog

| Model | API pricing per MTok | ChatGPT credits per 1M | Context / max output | Reasoning effort support / default | Headline benchmark | Knowledge cutoff | Confidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `gpt-5.5` | input $5.00; cached $0.50; output $30.00. Long-context sessions above 272K input apply 2x input and 1.5x output | input 125; cached 12.5; output 750 | 1,050,000 / 128,000 | `none`, `low`, `medium`, `high`, `xhigh`; default `medium` | SWE-bench Verified about 88.7% (MEDIUM/SECONDARY); Terminal-Bench 2.0 82.7% (MEDIUM/SECONDARY); SWE-bench Pro 58.6% (SECONDARY) | 2025-12-01 | HIGH/PRIMARY for pricing, credits, limits, effort, cutoff; benchmarks as tagged |
| `gpt-5.4` | input $2.50; cached $0.25; output $15.00. Long-context sessions above 272K input apply 2x input and 1.5x output | input 62.5; cached 6.25; output 375 | 1,050,000 / 128,000 | `none`, `low`, `medium`, `high`, `xhigh`; default `none` | SWE-bench Pro about 57.7-59.1% at `xhigh` (SECONDARY); SWE-bench Verified about 80% (LOW-MEDIUM/SECONDARY) | 2025-08-31 | HIGH/PRIMARY for pricing, credits, limits, effort, cutoff; benchmarks as tagged |
| `gpt-5.4-mini` | input $0.75; cached $0.075; output $4.50 | input 18.75; cached 1.875; output 113 | 400,000 / 128,000 | reasoning supported; exact level enumeration, `xhigh` support, and default NEEDS VERIFICATION | No published SWE-bench figure | 2025-08-31 | HIGH/PRIMARY for pricing, credits, limits, cutoff; effort enumeration NEEDS VERIFICATION |

## Effort Token Multipliers

COMMUNITY-MEASURED, NOT official; SECONDARY/LOW. Values are relative to `medium = 1x`.

| Effort | Approximate relative token burn | Confidence |
| --- | --- | --- |
| `none` / `minimal` | about 0.1x | COMMUNITY-MEASURED/LOW |
| `low` | about 0.3x | COMMUNITY-MEASURED/LOW |
| `medium` | 1x | COMMUNITY-MEASURED/LOW |
| `high` | about 3-5x | COMMUNITY-MEASURED/LOW |
| `xhigh` | about 8-15x | COMMUNITY-MEASURED/LOW |

OpenAI does not publish official per-effort token multipliers. Treat this table as a planning aid
for quota risk, not a billing guarantee.

## Availability Caveats

Never pin any `-codex` model under ChatGPT-subscription auth. The entire `-codex` family, including
`gpt-5.3-codex`, `gpt-5.2-codex`, and `gpt-5.1-codex-*`, is API-key-only and returns HTTP 400 under
subscription auth with this error: "The '<model>' model is not supported when using Codex with a
ChatGPT account." This caveat is HIGH/PRIMARY from OpenAI Codex sources.

`gpt-5.2-codex` and `gpt-5.3-codex` were sunset for ChatGPT subscriptions effective 2026-06-02
(HIGH/PRIMARY from OpenAI Codex sources, with community corroboration). `codex-session` and
`cog codex-runner` profiles must pin only `gpt-5.5`, `gpt-5.4`, or `gpt-5.4-mini` under
subscription auth.

The model picker can show a model that still returns HTTP 400 because frontend availability can drift
from backend availability. Do not trust the picker alone.

The subscription picker lineup confirmed on 2026-06-19 is `gpt-5.5`, `gpt-5.4`, and
`gpt-5.4-mini` (HIGH/PRIMARY). The latest confirmable Codex CLI release is 0.141.0, dated
2026-06-18 (HIGH/PRIMARY from the Codex changelog).

## Tier Intuition

`gpt-5.5 @ medium` is the quality default. OpenAI's latest-model guidance names medium the
recommended balanced default, and `gpt-5.5` carries the strongest available quality signal among the
subscription-selectable models.

`high` is escalation only. It can multiply token burn by roughly 3-5x according to
community-measured data, so it should be reserved for stuck, unusually complex, or high-stakes work
rather than routine defaults.

`gpt-5.4 @ high` is an anti-pattern with nuance. `gpt-5.4` is about half the per-token credit cost of
`gpt-5.5`, but high effort can erase that saving, and `gpt-5.4` defaults to `none`, so jumping
directly to `high` is a large reasoning-budget leap. Reach for `gpt-5.5` before pushing `gpt-5.4` to
high.

## Confidence and Uncertainty

API pricing, ChatGPT credit metering, context and output windows, effort support and defaults,
knowledge cutoffs, subscription availability, the `-codex` API-key-only caveat, the 2026-06-02
sunset, and Codex CLI 0.141.0 are HIGH/PRIMARY from the orchestrator's 2026-06-19 sweep of official
OpenAI sources.

`gpt-5.4-mini` pricing, credits, context, max output, and knowledge cutoff are HIGH/PRIMARY. Its
exact effort-level enumeration, `xhigh` support, and default are NEEDS VERIFICATION because the
primary per-model page did not enumerate them.

SWE-bench figures are SECONDARY where supplied by leaderboards or aggregators. OpenAI de-emphasized
SWE-bench Verified in Feb 2026, so those figures should remain qualified even when useful for rough
comparison.

The effort multiplier table is COMMUNITY-MEASURED/LOW and is not an official OpenAI billing or
quota guarantee.
