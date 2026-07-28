# Plan Vault Trust Model

The global vault is user data, so it lives in XDG DATA and is implicitly trusted. It is outside project checkouts, can be tracked by the user as a normal repository, and does not depend on any one repo being writable.

Project-local vaults are different. A checked-out repository can carry `.cog/config.sh` and a `project.sh` under its local plan dir (`.cog/plans/project.sh` by default, or the `COG_PLAN_LOCAL_DIR` override), so loading it automatically would let a project influence plan resolution. The local vault is therefore inert until `cog plan trust` records a fingerprint in XDG STATE. The fingerprint hashes `.cog/config.sh` together with the `project.sh` under the _configured_ local dir, so trust tracks exactly the local store that resolution will select. This mirrors direnv and mise: local project behavior exists, but activation is deliberate and tied to the current on-disk metadata.

Project identity combines a readable slug with a hash of the git identity alone:

```text
<slug>-<first-16-hex-of-sha256(git-identity)>
```

The git identity prefers `remote.origin.url`; without a remote, it falls back to the realpath of the git common directory, which is shared by every worktree of a repository. Keying on the git identity alone — not the per-checkout realpath — is deliberate: all worktrees of one repository, and a repository that is moved on disk, coalesce to a single vault entry instead of forking into separate keys. Each checkout's realpath is recorded in `COG_PLAN_ROOTS` inside `project.sh` (a moved or additional checkout is appended, repairing rather than forking). The slug is likewise derived from the git identity (the remote basename, or the repository directory name) so it stays stable across worktrees. For a non-git directory the identity falls back to the directory's own realpath, so unrelated plain directories still get distinct keys. The slug keeps paths inspectable, while the hash keeps keys stable enough for machine use.

Trust is stored in XDG STATE rather than DATA because it is local machine state, not portable plan content. Editing the trusted local config or metadata can change the fingerprint and require re-trusting, which is intentional: the user re-approves the local behavior after meaningful local inputs change.
