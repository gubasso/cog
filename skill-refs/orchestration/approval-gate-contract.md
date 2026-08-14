# Approval-Gate Contract

An **operator-approval gate** is a unit of work that must not complete on machine judgment alone: a human has to approve the work before the executor reports it done. The hard constraint is **proxy-mistrust** — the gate executor runs in a fresh context reached only through its orchestrating coordinator, so any approval the coordinator _relays_ ("the user said yes") is unverifiable and must be rejected. Without a side channel this deadlocks: the executor can never be satisfied, and declaring completion anyway defeats the gate.

The escape hatch is a **hash-bound approval file** the human writes directly and the executor reads itself. Because the file lives outside the coordinator's reach and the check re-hashes the artifact as it stands now, a relayed claim can never satisfy the gate — and never needs to.

## Mechanics

`cog gate` owns the deterministic verbs; the executor never inlines the rule. The artifact is the file under approval — the executor's input, its prepared plan, or whatever single file states the work the human is signing off.

```bash
# The human, out of band, after reviewing the artifact:
cog gate approve --gate-id <id> --artifact <file> [--approver <name>] [--notes <text>]

# The gate executor, at its terminus, before reporting done:
cog gate check-approval --gate-id <id> --artifact <file> [--ttl <secs>]
```

`approve` writes `${XDG_STATE_HOME:-~/.local/state}/cog/approvals/<gate-id>.json` binding the approval to the SHA-256 of the artifact at approval time. `check-approval` exits `0` only when all hold:

- an approval file for `<gate-id>` exists (`missing` otherwise),
- its recorded `content_hash` still equals the artifact's current hash — editing the artifact after approval invalidates it (`hash-mismatch`),
- the approval is within TTL, default 900s (`stale` otherwise).

Any other outcome exits non-zero with a JSON verdict naming the `status`. `cog gate prune-approvals` clears expired approval files.

## Executor obligation

A gate executor gates its terminal result on `cog gate check-approval` exit `0`. It never accepts a coordinator-relayed approval, and it never reports completion around the gate. If the check fails, the executor stops and reports the `status` so the human can run `cog gate approve` (or re-approve after a legitimate edit).

## Coordinator obligation

The coordinator surfaces the exact `cog gate approve` command for the human to run; it does not relay approval on the human's behalf. This keeps the human's approval on a channel the executor can verify.
