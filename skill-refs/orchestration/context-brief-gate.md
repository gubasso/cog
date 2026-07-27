# Context-brief gate

Single source of truth for the context-brief gate. Every fresh-context-boundary orchestrator — one
that hands substantive work (planning, review, implementation) to an Agent subagent or a
`cog codex-runner` Codex job — carries a short in-body imperative that points here and honors it with
a real `cog context-brief build`/`validate` call. This file owns the full contract; the general brief
shape is `orchestration/context-brief-contract.md`.

## Directive

Before dispatching to any fresh-context worker, build the worker's input as a validated context brief
from your whole accumulated raw context: attach the raw request as-is, author an oriented objective,
carry the full substance and load-bearing artifacts, and omit your own verdict. Build the brief with
`cog context-brief build --request …` and confirm it with `cog context-brief validate …` before
dispatch.
