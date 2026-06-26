# Context Handoff and the Context-Builder

## The problem

A fresh-context worker — a delegated Agent, a forked skill, or a Codex exec — does not inherit the
orchestrator's conversation. To act well it needs the right context, but piping it the whole
transcript is the wrong fix: it reintroduces the token bloat and attention degradation that isolated
contexts exist to avoid. The job is to hand over a *brief*, not a *transcript*.

This is why `review-loop` (which runs forked) and the dual-engine coordinators each assemble a
curated brief rather than forwarding the chat. The `context-builder` skill and `cog context-brief`
command make that brief a single, validated, reusable artifact instead of per-skill prose.

## Principles

**Best-constructed, not transcribed and not lossy.** Multi-agent systems win because each worker
reasons in its own clean context. The goal is the input that lets the worker do its best work: a
well-oriented brief that carries the full substance of the session — not the raw transcript, and not a
summary that drops what matters.

**Oriented summary, raw request attached, full substance carried.** The brief leads with an Objective
crafted from the whole session, and `cog context-brief build --request` attaches the raw request
verbatim as cheap insurance. Summarize narrative for clarity, but carry the full substance — decisions,
research, findings, and especially generated artifacts like a session plan — because a prompt like
"given this context, implement this" depends on all of it.

**Pointers over payloads for the large stuff.** Large or external artifacts are referenced by absolute
path so the worker retrieves them on demand; load-bearing plans and excerpts are inlined. This keeps
the brief focused while still complete.

**One deliberate omission.** The coordinator leaves out its own verdict or proposed solution, so an
independent worker forms its own judgment. This is the bias isolation that makes a second engine worth
running (see [ADR-0043](../decisions/0043-best-constructed-input-standard.md), which supersedes
ADR-0035).

**Inline, not delegated.** Context-building cannot be handed to a blind subagent — the source
material lives in the orchestrator's own window. The builder runs inline; only execution on the
finished brief is delegated.

## Why a contract plus a command

The structural shape lives once in `skill-refs/orchestration/context-brief-contract.md`; the
deterministic scaffold/build/validate lives in `cog context-brief`; the judgment of what to put in
each section lives in the `context-builder` skill. Orchestrators reuse all three instead of
re-deriving the brief format. See
[ADR-0042](../decisions/0042-context-builder-shared-capability.md).

## References

These external sources informed the brief schema and the principles above:

- Anthropic — Effective context engineering for AI agents:
  <https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents>
- Anthropic — How we built our multi-agent research system:
  <https://www.anthropic.com/engineering/multi-agent-research-system>
- Anthropic — Effective harnesses for long-running agents:
  <https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents>
- LangChain — Multi-agent handoffs:
  <https://docs.langchain.com/oss/python/langchain/multi-agent/handoffs>
- Microsoft Agent Framework — Conversation compaction:
  <https://learn.microsoft.com/en-us/agent-framework/agents/conversations/compaction>
