# Plan-mode gate

Single source of truth for the Phase-0 plan-mode gate. Every Claude `executor-*` orchestrator carries a short in-body imperative that points here; this file owns the full protocol. The gate lives on the orchestrator layer — the caller a user launches gates once at entry, then delegates to gate-free plan/review workers. Plan-mode detection stays probabilistic in skill prose.

## Directive

If Claude Code **plan mode** is active — a system-reminder says plan mode is on or that you must not make edits — **STOP** before any other work: parsing args, researching, interviewing, delegating, or writing. Tell the user in one line to exit plan mode (`Shift+Tab`) and re-invoke the skill. Do not call `ExitPlanMode`, and do not silently continue.
