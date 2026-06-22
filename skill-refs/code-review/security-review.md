# Security Review

Load when the diff touches authentication, authorization, user input, external systems,
cryptography, file I/O with user-controlled paths, or anything that ends up running as code.

## Trigger heuristics

Open when the diff has any of:

- Auth/session/token handling.
- Database queries built from inputs.
- File system access with caller-supplied paths.
- Shell exec, eval, dynamic require/import.
- Cryptography (encryption, hashing, signing, random number generation).
- Network calls to external services (especially with auth).
- Deserialization (JSON, pickle, msgpack, yaml from untrusted sources).
- Secrets, API keys, environment variables.

## The source-to-sink discipline

For every security finding, the report must trace:

1. **Source.** Where untrusted input enters. CLI flag, HTTP body, message queue, database row
   populated by another service.
2. **Sink.** Where it becomes dangerous. `eval`, raw SQL, `system()`, file `open()`, deserializer,
   redirect URL, response header, log line containing credentials.
3. **Path.** Every intermediate file:line between source and sink. If a sanitizer breaks the path,
   the finding is invalid — drop or downgrade to `[question]`.

This is the source-to-sink reachability test from
[llm-review-discipline.md](llm-review-discipline.md); apply it religiously.

## Injection categories

### SQL injection

```python
# Bad
db.execute(f"SELECT * FROM users WHERE id = {user_id}")
db.execute("SELECT * FROM users WHERE id = '%s'" % user_id)

# Good
db.execute("SELECT * FROM users WHERE id = ?", (user_id,))
```

Anything that builds SQL via string concatenation, f-strings, `.format()`, or template substitution
is `[blocking]` unless the inserted value is a column/table name that cannot be parameterized — in
which case it must be whitelist-validated.

### Command injection

```bash
# Bad
ssh user@"$host" "ls $dir"

# Good (still shaky in bash — prefer not to pass user input to a remote shell at all)
ssh user@"$host" -- ls -- "$dir"
```

```python
# Bad
subprocess.run(f"git log {user_branch}", shell=True)

# Good
subprocess.run(["git", "log", user_branch])
```

Any `shell=True`, any `os.system()`, any string-built command line. `[blocking]`.

### Path traversal

```python
# Bad
open(f"/data/{user_filename}")     # user_filename = "../../etc/passwd"

# Good
import os
safe_path = os.path.realpath(os.path.join("/data", user_filename))
if not safe_path.startswith("/data/"):
    raise ValueError("path escapes base directory")
open(safe_path)
```

Test: does the path code defend against `../`, absolute paths, and symlinks? If not, `[blocking]`.

### Code execution

`eval`, `exec`, `Function()` constructor (JS), `import` with dynamic name, `pickle.loads` on
untrusted data, `yaml.load` (not `safe_load`). All `[blocking]` on untrusted input. Even on trusted
input, prefer a safer alternative.

### XSS / template injection (web)

- Server-side templating with `|safe` / raw output of user content.
- React: `dangerouslySetInnerHTML` with user input.
- Direct DOM `.innerHTML = userText`.

`[blocking]` unless the input has gone through a documented sanitizer (DOMPurify, `bleach`, etc.).

## Authentication and session

- **Comparisons of secrets** must use constant-time comparison. `if token == expected:` in Python
  leaks via timing — use `hmac.compare_digest`. In Node, `crypto.timingSafeEqual`.
- **Session ID generation**: must use a CSPRNG (`secrets`, `crypto.randomBytes`, not
  `random.random`/`Math.random`).
- **Password hashing**: bcrypt, Argon2, scrypt, or PBKDF2 with a high work factor. Never raw SHA-256
  / MD5. Never reversible.
- **Session expiry**: every session has a finite lifetime; logout is observable across servers.
- **Cookie flags**: `HttpOnly`, `Secure`, `SameSite` set on auth cookies.

## Authorization

The classic mistake: authenticating but not authorizing.

```python
# Bad — anyone logged in can fetch anyone's order
@require_login
def order_detail(request, order_id):
    return Order.objects.get(id=order_id)

# Good
def order_detail(request, order_id):
    return Order.objects.get(id=order_id, user=request.user)
```

For every endpoint that reads or mutates user-scoped data, check that the query is filtered by the
actor's identity, not just that the actor is authenticated.

Check **insecure direct object reference** (IDOR): any time an ID from the request body or URL
fetches a record without a user-scope check.

## Cryptography

- **No homegrown crypto.** Flag any custom encryption, custom hashing, or custom MAC construction as
  `[blocking]`. Use a library.
- **Algorithm choice**: AES-GCM or ChaCha20-Poly1305 for AEAD; SHA-256 or BLAKE3 for hashing;
  Ed25519 for signing. Avoid MD5, SHA-1, DES, RC4.
- **Key management**: keys not in code, not in env vars committed to git. Pull from a secret
  manager.
- **Nonce/IV reuse**: each encryption must use a fresh nonce. Static nonces are `[blocking]`.
- **Random number generation**: cryptographic context requires `secrets`, `crypto`, `getrandom`, or
  platform-equivalent. Not `random`, `rand`, `Math.random`.

## Secrets in code

Patterns to flag automatically:

- Strings matching `^[A-Za-z0-9_-]{32,}$` assigned to names containing `key`, `token`, `secret`,
  `password`.
- AWS access key format (`AKIA[0-9A-Z]{16}`).
- GitHub PAT (`ghp_[A-Za-z0-9]{36}`).
- Private key blocks (`-----BEGIN`).
- `.env` files in the diff.

Even one occurrence is `[blocking]` AND the secret must be rotated. The reviewer's job is to say so
explicitly: "Rotate this credential immediately and force-push to remove from history."

## Logging secrets

- Logging request bodies that may contain credentials.
- Logging error messages that include the raw payload.
- Logging headers (especially `Authorization`).
- Stack traces showing local variables containing secrets.

For each logger call in the diff, check what's being logged. Token in the message → `[blocking]`.

## Deserialization

- `pickle.loads`, `yaml.load`, `marshal.loads`, `JSON.parse` of code-bearing payloads — all unsafe
  on untrusted input.
- Custom deserializers must validate types before constructing objects.
- Polymorphic deserialization (`@class` tags) must whitelist allowed types.

## HTTP-specific

- **CSRF**: state-changing endpoints behind cookies need CSRF tokens.
- **CORS**: `Access-Control-Allow-Origin: *` paired with `Access-Control-Allow-Credentials:
  true`
  is invalid per spec and a critical misconfig.
- **Open redirect**: `Location: $user_supplied_url` without origin check.
- **SSRF**: server fetching a URL the user controls — restrict to allowlist of hosts/protocols.
- **TLS**: validating the certificate chain. Flag any `verify=False`, `rejectUnauthorized:
  false`,
  or `tls.InsecureSkipVerify`.

## Dependency security

- New dependency added: is it actively maintained? Audit the publisher.
- Lockfile present and updated?
- Any direct deps with known CVEs (npm audit, pip-audit, cargo-audit)?
- Transitive dep upgrades that change behavior?

## Rate limiting and DoS

- Endpoints that allocate large amounts (CPU, memory, DB rows) per request need rate limits.
- Regular expressions on user input: catastrophic backtracking risk (`/(a+)+/` over a long string).
  Use re2/Hyperscan or rewrite the pattern.
- Decompression bombs: zip/gzip of untrusted input can expand to gigabytes. Limit decompressed size.

## Owasp Top 10 (2021 → 2026)

Use as a checklist, not a script. Each item maps to one or more rules above:

1. Broken access control → "Authorization" section.
2. Cryptographic failures → "Cryptography".
3. Injection → "Injection categories".
4. Insecure design → architectural; consult [architecture-review.md](architecture-review.md).
5. Security misconfiguration → CORS, TLS, default creds.
6. Vulnerable & outdated components → "Dependency security".
7. Identification & auth failures → "Authentication and session".
8. Software & data integrity failures → unsigned deserialization, unsigned updates.
9. Logging & monitoring failures → secret logging, no audit trail for security-relevant events.
10. Server-side request forgery → "HTTP-specific" SSRF.

## See also

- [process.md](process.md), [llm-review-discipline.md](llm-review-discipline.md) — base workflow,
  with the source-to-sink discipline.
- [code-quality-universal.md](code-quality-universal.md) — error swallowing,
  defensive-programming-gone-wrong (often hides security bugs).
- [common-bugs.md](common-bugs.md) — language-specific footguns.
- Project-specific security policy in `SECURITY.md` if present.
