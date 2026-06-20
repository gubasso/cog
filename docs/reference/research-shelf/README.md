# Research Shelf

The research shelf is the repository store for dated, sourced findings that skills can reuse instead
of repeating live web research on every run. The shelf index is
`docs/reference/research-shelf/index.jsonl`; each line is one JSON object recorded by
`cog research-shelf record`.

## Consumer Contract

Consuming skills read relevant shelf entries before duplicating research. An entry is reusable when
its `revalidate-after` date has not passed and the skill judges its `topic-tags` and
`consuming-skills` to match the current task. That matching is the consuming skill's judgment over
the entries it reads; `cog research-shelf` does not select entries by tag or skill.

When a relevant entry is overdue, stale, or missing for the needed topic, the skill re-researches the
topic from current sources and records the refreshed finding through `cog research-shelf record`.
Skills cite or summarize shelf entries as supporting context; they do not copy old web findings into
skill bodies as permanent facts.

The shelf contract is intended for `lean-plan-and-review-skills`, `plan-*`, `review-plan-*`, and
executor skills. Those skills should treat the shelf as reusable context, not as deterministic
mechanics. Persistence, validation, IDs, dates, and source shape are owned by `cog research-shelf`.

## Entry Fields

Each entry records:

- `id` - stable shelf record identifier.
- `recorded-date` - date the finding was recorded.
- `revalidate-after` - date after which the finding must be refreshed before reuse.
- `topic-tags` - searchable topic labels.
- `consuming-skills` - skill families expected to consume the entry.
- `sources` - cited source objects with `title`, `publisher`, `url`, and `access-date`.
- `stable-summary` - concise finding for downstream skills.
