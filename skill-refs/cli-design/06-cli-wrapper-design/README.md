# 06 — CLI Wrapper Design

> Part of the general [CLI design principles](../README.md).

CLIs that **wrap and orchestrate other CLI binaries** (think `gh` calling `git`, `mise` calling
toolchain binaries, `kubectl` calling out to plugins, custom workflow CLIs calling `cargo` / `npm` /
`docker`) are themselves Unix utilities with a uniquely demanding job: be a _translator and
shepherd_ for another process while still respecting the POSIX/GNU contract every CLI inherits.

This is a different problem from designing a fresh CLI from scratch. If you are not wrapping another
binary, you can skip this entire chapter — go back to [00 — Architecture](../00-architecture.md).

## Two concerns, two chapters

| Concern                 | Question it answers                                                                                  | Chapter                                              |
| ----------------------- | ---------------------------------------------------------------------------------------------------- | ---------------------------------------------------- |
| **Typing & validation** | "How do I structure my code so I can't accidentally generate malformed args?"                        | [typing-and-validation.md](typing-and-validation.md) |
| **Process & POSIX**     | "How do I reliably invoke a subprocess while respecting argv layout, signals, exit codes, and TTYs?" | [process-and-posix.md](process-and-posix.md)         |
| **Checklist**           | "What must be true before I declare this wrapper shippable?"                                         | [checklist.md](checklist.md)                         |

Read both, in this order. The first tells you _what_ to build; the second tells you _how_ to run it.

## When you need this chapter

- You are writing a CLI whose primary job is launching one or more other CLI binaries.
- You are writing a higher-level workflow tool that calls `git`, `cargo`, `npm`, `gh`, `kubectl`,
  etc.
- You are writing a shim or proxy that adds defaults, validates inputs, or restricts access to a
  wrapped command.
- You are writing a plugin host (a tool that delegates to `<tool>-<plugin>` binaries on `PATH`).

## When you don't

- You are writing a CLI that does its own work in-process (compute, parse, render). No subprocess in
  sight.
- You shell out occasionally for one specific operation. That's an adapter (see
  [00 — Architecture](../00-architecture.md), `adapters/`), not a wrapper-CLI architecture.

## The single most important principle

**Make the wrapper's grammar small and explicit. Keep the wrapped command mostly opaque. Avoid argv
rewriting unless you have a narrow, stable reason.**

Every rule in the two chapters descends from this. Wrappers that aggressively rewrite their child's
argv become fragile — every new flag the child adds is a potential breakage in the wrapper.

## Quick checklist

For the full checklist, see [checklist.md](checklist.md). Highlights:

- [ ] Wrapper's own flags are **before** the subcommand; everything after `--` passes through
      verbatim.
- [ ] Args to the wrapped binary are built from a typed model, not concatenated strings.
- [ ] The build step (`to_args()`) is pure and unit-testable.
- [ ] Process invocation respects exec-vs-spawn semantics for your use case.
- [ ] SIGINT/SIGTERM forward to the child by default.
- [ ] Child's exit code passes through unless you have a documented reason to remap.
- [ ] No PATH-search surprises: resolve the binary explicitly.

## See also

- [General CLI design index](../README.md)
- [00 — Architecture](../00-architecture.md) — if your wrapper is also a "normal" CLI, the
  architecture rules still apply.
- [02 — Error Messages](../02-error-messages.md) — exit-code mapping when the wrapper has to
  translate child failures.
- [05 — Designing for LLM Agents](../05-designing-for-llm-agents.md) — wrappers are commonly
  consumed by agents.
