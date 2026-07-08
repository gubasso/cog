# osc authentication in headless and devcontainer environments

Tier-1 remediation reference for the `creds_invalid` auth class reported by `cog osc-preflight`.
This content is generic openSUSE Build Service (OBS) knowledge; it holds no project- or
host-specific data. Project-specific overrides belong in the caller-supplied `$OBS_DOCS_DIR`.

## Where credentials live

`osc` reads its configuration from an `oscrc` file, by default `~/.config/osc/oscrc` (override with
the `OSC_CONFIG` environment variable or the `-c <path>` flag). Each `[<apiurl>]` section holds the
`user` and the credential for that API host, plus a `credentials_mgr_class` that selects how the
secret is stored and retrieved.

## Why keyrings fail in containers

`osc`'s default credentials manager stores the password in the desktop keyring (Secret Service /
`keyutils`). Headless shells, CI runners, and devcontainers usually have no running keyring daemon,
so retrieval fails and preflight reports `keyring_unavailable` or `creds_invalid`. The fix is to
select a manager that does not depend on a keyring.

## Headless-friendly oscrc

Use the obfuscated config-file credentials manager, which stores the (obfuscated) secret directly in
`oscrc` — no keyring required:

```ini
[general]
apiurl = https://api.opensuse.org

[https://api.opensuse.org]
user = <username>
credentials_mgr_class = osc.credentials.ObfuscatedConfigFileCredentialsManager
```

After writing the section, run a read-only probe to confirm the credential resolves:

```bash
osc -A https://api.opensuse.org api /person/<username>
```

A `401`/`403` means the secret is wrong or expired (re-seed it); a network error means egress, proxy,
DNS, or TLS is the problem, not credentials.

## Re-seeding a credential

Re-run the interactive config only in an environment where it is safe to enter a secret, or write the
`oscrc` section directly from a secret already provisioned to the environment. Never echo the secret
into logs, and never trigger interactive `osc user` from inside an automated skill run — surface the
`creds_invalid` result and let the operator re-seed.

## Related auth classes

- `keyring_unavailable`: switch to `ObfuscatedConfigFileCredentialsManager` as above.
- `network`: check egress, proxy, DNS, TLS, and firewall before retrying any auth step.

## Further reading (public, optional)

- openSUSE `osc` documentation: <https://opensuse.github.io/osc/>
- OBS user guide: <https://openbuildservice.org/help/manuals/obs-user-guide/>
