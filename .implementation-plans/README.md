# Implementation Plans

This directory stores implementation plans generated for staged agent execution.

`QUEUE.yaml` is the source of truth for plan status, order, dependencies, and execution prompts.
Plans live under `plans/` as either a single self-contained markdown file or a directory containing
round files and an inner `QUEUE.yaml`.

Execute one round at a time. Status lives in YAML; files and directories do not move between states.
