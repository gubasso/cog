# Bootstrap git-identity preflight routine

The single routine a `bootstrap-*` worker follows before it writes any file that carries the project's author or copyright identity (a `Cargo.toml` `authors` entry, a LICENSE copyright holder). It reads the repository's own git identity deterministically and uses it, or pauses with a step-by-step remediation when the identity is not configured — never guessing a name or email from session context.

The split is fixed: `cog` owns the deterministic resolution (`cog git-identity check`), which reads `user.name`/`user.email` exactly as git resolves them (a repo-local value overrides the global one — the same identity the repo's commits carry). The worker owns the judgment: whether identity is required for this run, and how to seed it into the artifact it is about to write.

## Routine

1. **Resolve identity.** Before writing an identity-bearing field, read the repo's git identity:

   ```bash
   cog git-identity check --json
   ```

   It emits `{ok, name, email, author_string, name_source, email_source, missing, reason}` and exits non-zero when identity is not fully configured. `author_string` is `"<name> <email>"` when both resolve; `name_source`/`email_source` are `local`, `global`, or `system`; `missing` lists the unset keys (`user.name`, `user.email`).

2. **Use it when `ok` is `true`.** Populate the field deterministically from the resolved values — `author_string` for a `Cargo.toml` `authors` entry, `name` (and, where the format wants it, `email`) for a LICENSE copyright holder. Never substitute an email or name drawn from the session, memory, or the operating environment.

3. **Pause when `ok` is `false`.** Do not write a guessed value and do not proceed with the identity-bearing step. Stop and present the operator a step-by-step to configure the identity, then re-run once they confirm:

   ```text
   Git identity is not configured for this repository.
   Set your name and email, then re-run this bootstrap step:

     git config user.name  "Your Name"
     git config user.email "you@example.com"

   Add --global to either command to apply it to every repo instead of just this one:

     git config --global user.name  "Your Name"
     git config --global user.email "you@example.com"
   ```

   Tailor the placeholder name/email in the prose, but keep the two commands verbatim. When only one key is missing (see `missing`), name just that key so the operator runs the minimal fix.
