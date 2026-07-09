# Approval-Gate Contract

An **operator-approval gate** is a queue round that must not complete on machine judgment alone: a
human has to approve the work before the executor flips the round to `done`. The hard constraint is
**proxy-mistrust** — the gate executor runs in a fresh context reached only through its orchestrating
coordinator, so any approval the coordinator *relays* ("the user said yes") is unverifiable and must be
rejected. Without a side channel this deadlocks: the executor can never be satisfied, and hand-editing
the queue to force it through defeats the gate.

The escape hatch is a **hash-bound approval file** the human writes directly and the executor reads
itself. Because the file lives outside the coordinator's reach and the check re-hashes the round as it
stands now, a relayed claim can never satisfy the gate — and never needs to.

## Mechanics

`cog gate` owns the deterministic verbs; the executor never inlines the rule.

```bash
# The human, out of band, after reviewing the round:
cog gate approve --round-id <id> --round-path <round-file> [--approver <name>] [--notes <text>]

# The gate executor, at its terminus, before flipping the round to done:
cog gate check-approval --round-id <id> --round-path <round-file> [--ttl <secs>]
```

`approve` writes `${XDG_STATE_HOME:-~/.local/state}/cog/approvals/<round-id>.json` binding the approval
to the SHA-256 of the round file at approval time. `check-approval` exits `0` only when all hold:

- an approval file for `<round-id>` exists (`missing` otherwise),
- its recorded `content_hash` still equals the round file's current hash — editing the round after
  approval invalidates it (`hash-mismatch`),
- the approval is within TTL, default 900s (`stale` otherwise).

Any other outcome exits non-zero with a JSON verdict naming the `status`. `cog gate prune-approvals`
clears expired approval files.

## Executor obligation

A gate executor gates its `done` flip on `cog gate check-approval` exit `0`. It never accepts a
coordinator-relayed approval, and it never hand-edits the queue to bypass the gate. If the check fails,
the executor stops and reports the `status` so the human can run `cog gate approve` (or re-approve
after a legitimate edit).

## Coordinator obligation

The coordinator surfaces the exact `cog gate approve` command for the human to run; it does not relay
approval on the human's behalf. This keeps the human's approval on a channel the executor can verify.
