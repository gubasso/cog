# Sources & Refresh Provenance

Tracks where every file under this skill's reference tree comes from, so the content can be re-synced as upstreams evolve. Update this file whenever you refresh a reference.

## Refresh policy

- Quarterly drift check: walk the table, fetch the upstream, eyeball-diff against our distilled version, refresh material changes only.
- Major-version bumps in any framework (React, Svelte, etc.) trigger an immediate refresh for the matching language file.
- New entries in the maintainer's private CLI-design or per-language CLI-spec notes (tracked outside this shipped tree) trigger refresh of the matching `cli-design/<file>.md` or `languages/<lang>/code-review-guide.md` CLI subsection.

The "Last synced" column starts at the skill's creation date. When refreshing, bump it.

## Cross-cutting references

| File                        | Upstream                                                                                                          | Local canon (if any) | Last synced |
| --------------------------- | ----------------------------------------------------------------------------------------------------------------- | -------------------- | ----------- |
| `process.md`                | <https://github.com/awesome-skills/code-review-skill/blob/main/SKILL.md> (process sections)                       | —                    | 2026-05-22  |
| `code-quality-universal.md` | <https://github.com/awesome-skills/code-review-skill/blob/main/reference/code-quality-universal.md>               | —                    | 2026-05-22  |
| `architecture-review.md`    | <https://github.com/awesome-skills/code-review-skill/blob/main/reference/architecture-review-guide.md>            | —                    | 2026-05-22  |
| `performance-review.md`     | <https://github.com/awesome-skills/code-review-skill/blob/main/reference/performance-review-guide.md>             | —                    | 2026-05-22  |
| `security-review.md`        | <https://github.com/awesome-skills/code-review-skill/blob/main/reference/security-review-guide.md> + OWASP Top 10 | —                    | 2026-05-22  |
| `common-bugs.md`            | <https://github.com/awesome-skills/code-review-skill/blob/main/reference/common-bugs-checklist.md>                | —                    | 2026-05-22  |
| `llm-review-discipline.md`  | New. Synthesized from arxiv 2401.16310, 2601.18844, 2411.03079; Datadog Security Labs blog                        | —                    | 2026-05-22  |

## CLI chapters (distilled from local canon)

CLI design guidance now ships in-repo under `cli-design/`, distilled from the maintainer's private CLI-design notes (tracked outside this shipped tree). The shipped `cli-design/` tree is the **single source of truth** for runtime use; when the private notes update, refresh the distilled chapter to match.

| File                              | Local canon (authoritative)                                                                                          | Upstream (cross-reference) | Last synced |
| --------------------------------- | -------------------------------------------------------------------------------------------------------------------- | -------------------------- | ----------- |
| `cli/index.md`                    | `tech/programming/cli-design/README.md`                                                                              | —                          | 2026-05-22  |
| `cli/architecture.md`             | `tech/programming/cli-design/00-architecture.md`                                                                     | —                          | 2026-05-22  |
| `cli/logging-and-output.md`       | `tech/programming/cli-design/01-logging-and-output.md`                                                               | —                          | 2026-05-22  |
| `cli/error-messages.md`           | `tech/programming/cli-design/02-error-messages.md`                                                                   | —                          | 2026-05-22  |
| `cli/config-precedence.md`        | `tech/programming/cli-design/03-config-precedence.md`                                                                | —                          | 2026-05-22  |
| `cli/designing-for-llm-agents.md` | `tech/programming/cli-design/05-designing-for-llm-agents.md`                                                         | —                          | 2026-05-22  |
| `cli/wrapper-design.md`           | `tech/programming/cli-design/06-cli-wrapper-design/`                                                                 | —                          | 2026-05-22  |
| `cli/testing-strategy.md`         | `tech/programming/cli-design/08-testing-and-quality/testing-strategy.md` + `08-testing-and-quality/testing-tools.md` | —                          | 2026-05-22  |
| `cli/checklist.md`                | `tech/programming/cli-design/99-checklist.md`                                                                        | —                          | 2026-05-22  |

## Language guides

Each file distills review heuristics from the named upstream plus local-canon CLI specs.

| File                         | Upstream                                                                                   | Local CLI canon                           | Last synced |
| ---------------------------- | ------------------------------------------------------------------------------------------ | ----------------------------------------- | ----------- |
| `languages/rust.md`          | <https://github.com/awesome-skills/code-review-skill/blob/main/reference/rust.md>          | `tech/languages/rust/cli-spec/`           | 2026-05-22  |
| `languages/python.md`        | <https://github.com/awesome-skills/code-review-skill/blob/main/reference/python.md>        | `tech/languages/python/cli-spec/`         | 2026-05-22  |
| `languages/bash.md`          | (no upstream — original distillation)                                                      | `tech/languages/bash/cli-spec/`           | 2026-05-22  |
| `languages/typescript.md`    | <https://github.com/awesome-skills/code-review-skill/blob/main/reference/typescript.md>    | `tech/languages/javascript/typescript.md` | 2026-05-22  |
| `languages/javascript.md`    | (shares heuristics with typescript upstream)                                               | `tech/languages/javascript/`              | 2026-05-22  |
| `languages/go.md`            | <https://github.com/awesome-skills/code-review-skill/blob/main/reference/go.md>            | —                                         | 2026-05-22  |
| `languages/lua.md`           | (no upstream — original distillation)                                                      | —                                         | 2026-05-22  |
| `languages/r.md`             | (no upstream — original distillation)                                                      | `tech/languages/r/`                       | 2026-05-22  |
| `languages/react.md`         | <https://github.com/awesome-skills/code-review-skill/blob/main/reference/react.md>         | —                                         | 2026-05-22  |
| `languages/svelte.md`        | <https://github.com/awesome-skills/code-review-skill/blob/main/reference/svelte.md>        | —                                         | 2026-05-22  |
| `languages/django.md`        | <https://github.com/awesome-skills/code-review-skill/blob/main/reference/django.md>        | —                                         | 2026-05-22  |
| `languages/c.md`             | <https://github.com/awesome-skills/code-review-skill/blob/main/reference/c.md>             | —                                         | 2026-05-22  |
| `languages/css-less-sass.md` | <https://github.com/awesome-skills/code-review-skill/blob/main/reference/css-less-sass.md> | —                                         | 2026-05-22  |

## Config-file guides

| File                        | Upstream                                                                              | Last synced |
| --------------------------- | ------------------------------------------------------------------------------------- | ----------- |
| `configs/markdown.md`       | markdownlint docs <https://github.com/DavidAnson/markdownlint/blob/main/doc/Rules.md> | 2026-05-22  |
| `configs/yaml-toml.md`      | YAML 1.2 spec + TOML 1.0 spec                                                         | 2026-05-22  |
| `configs/dockerfile.md`     | hadolint rules <https://github.com/hadolint/hadolint/wiki>                            | 2026-05-22  |
| `configs/github-actions.md` | actionlint <https://github.com/rhysd/actionlint/blob/main/docs/checks.md>             | 2026-05-22  |

## Research references (research papers, not refreshed routinely)

These ground `llm-review-discipline.md`. No quarterly refresh; check on major findings.

> **Citation note:** `arXiv:2601.18844` (Du et al., Jan 2026) postdates common LLM training cutoffs and was verified real on 2026-06-15; the 2024 IDs predate it. Do not flag a citation as fabricated for being future-dated — fetch the arXiv abstract and verify first.

- Hou et al. "An Insight into Security Code Review with LLMs", arxiv 2401.16310.
- Du et al. "Reducing False Positives in Static Bug Detection with LLMs: An Empirical Study in Industry", arxiv 2601.18844.
- Liu et al. "Utilizing Precise and Complete Code Context to Guide LLM in Automatic False Positive Mitigation", arxiv 2411.03079.
- Datadog Security Labs, "Using LLMs to filter out false positives from static code analysis".
- Anthropic, "Skill authoring best practices", <https://docs.claude.com/en/docs/agents-and-tools/agent-skills/best-practices>.

## How to refresh

```bash
# 1. Fetch the upstream into a scratch dir
git clone --depth=1 https://github.com/awesome-skills/code-review-skill /tmp/cr-upstream

# 2. Diff against our distilled version
diff /tmp/cr-upstream/reference/rust.md \
     ~/.local/share/coding-agent-skills/review-code-deep/languages/rust.md

# 3. Incorporate material changes (new framework version, new anti-patterns, deprecated
#    advice). Preserve the file's distilled shape — don't re-import wholesale.

# 4. Bump the "Last synced" date in this file.

# 5. Run pre-commit on the changed files.
pre-commit run --files <changed>
```

For sources distilled from the maintainer's private notes (tracked outside this shipped tree), the equivalent is a simple diff and re-distillation. Always preserve the "review-time heuristics" framing; never copy the canon verbatim.

## Notes

- Upstream content is MIT-licensed (per `awesome-skills/code-review-skill/LICENSE`).
- Our distillations are original work; attribution to the upstream is via this file plus the per-file "See also" footers.
- When the local canon and the upstream conflict, **local canon wins** (it reflects this user's verified conventions).
