# Wrapper Design — Typing & Validation

> **See also.** The sibling chapter [Process & POSIX](./process-and-posix.md) covers the
> _invocation_ side: argv layout, `--` separator, exec vs spawn, signal forwarding, exit-code
> propagation, plugin namespacing, failure modes. Read both — this one is about _what you build_;
> the sibling is about _how you run it_.
>
> This chapter is part of [CLI Wrapper Design](./README.md) under the general
> [CLI design principles](../README.md).

Reference for building CLI programs that wrap other CLI tools using typed data structures.

## Core Principle

```text
Typed model  -->  to_args() / into_command()  -->  OS execution
(your domain)     (serialization boundary)         (subprocess / Command)
```

Model the wrapped CLI's domain as typed structures, validate at construction time, and serialize
into command arguments only at the execution boundary.

## Design Rules

1. **Type the domain, not the strings.** Flags become bools/enums, not scattered `.arg("--flag")`
   calls.
1. **Separate build from execution.** Builder produces a `Command` / `list[str]`; caller decides how
   to run it.
1. **Make invalid states unrepresentable.** Mutually exclusive flags = enum, not two bools.
1. **Error handling at the boundary.** Parse stdout/stderr into your own result types.
1. **Common execution interface.** A trait/protocol shared across all wrapped CLIs.

## Complexity Ladder

| Complexity      | Approach                                    | When to use                                   |
| --------------- | ------------------------------------------- | --------------------------------------------- |
| One-off calls   | Raw `Command` / `subprocess.run`            | Quick scripts, single invocations             |
| Light scripting | `xshell` / `duct` / `plumbum`               | Build scripts, CI pipelines                   |
| Serious wrapper | Typed structs + `Executable` trait/protocol | Wrapping a specific CLI with many subcommands |
| Full SDK        | Typed models + API client + error types     | Public library, multi-CLI orchestration       |

---

## Rust Implementation

### Basic: `std::process::Command` (stdlib builder)

```rust
use std::process::Command;

Command::new("git")
    .arg("commit")
    .arg("-m")
    .arg(message)
    .env("GIT_AUTHOR_NAME", name)
    .current_dir(&repo_path)
    .stdout(Stdio::piped())
    .status()?;
```

Fine for simple one-off calls. Gets messy with complex CLIs.

### Typed Wrapper Struct

```rust
pub struct GitCommit {
    message: String,
    amend: bool,
    sign: bool,
    author: Option<String>,
}

impl GitCommit {
    pub fn new(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
            amend: false,
            sign: false,
            author: None,
        }
    }

    // Consume self (idiomatic for builders — prevents partial reuse)
    pub fn amend(mut self) -> Self {
        self.amend = true;
        self
    }

    pub fn sign(mut self) -> Self {
        self.sign = true;
        self
    }

    pub fn author(mut self, author: impl Into<String>) -> Self {
        self.author = Some(author.into());
        self
    }

    /// Terminal method: converts typed struct into std::process::Command.
    /// This is the serialization boundary.
    pub fn into_command(self) -> Command {
        let mut cmd = Command::new("git");
        cmd.arg("commit").arg("-m").arg(&self.message);
        if self.amend {
            cmd.arg("--amend");
        }
        if self.sign {
            cmd.arg("-S");
        }
        if let Some(ref a) = self.author {
            cmd.arg("--author").arg(a);
        }
        cmd
    }
}
```

**Key decisions:**

- `self` (consuming) vs `&mut self` in builder methods — consuming is more idiomatic, prevents reuse
  of partial state.
- `into_command()` as the clean boundary between domain and OS.
- Don't bake `.status()` / `.output()` into the builder.

### Common Execution Trait

```rust
use std::io;
use std::process::{Command, ExitStatus, Output};

pub trait Executable {
    fn into_command(self) -> Command;

    fn run(self) -> io::Result<ExitStatus>
    where
        Self: Sized,
    {
        self.into_command().status()
    }

    fn output(self) -> io::Result<Output>
    where
        Self: Sized,
    {
        self.into_command().output()
    }

    fn capture(self) -> io::Result<String>
    where
        Self: Sized,
    {
        let output = self.into_command().output()?;
        Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
    }
}

impl Executable for GitCommit {
    fn into_command(self) -> Command {
        // ... same as above
    }
}
```

### Enum-Based Subcommand Modeling

```rust
/// Mutually exclusive flags as enum — invalid combinations are unrepresentable.
pub enum ResetMode {
    Soft,
    Mixed,
    Hard,
}

pub struct GitReset {
    mode: ResetMode,
    target: String,
}

/// Top-level subcommand dispatch.
pub enum GitCommand {
    Commit(GitCommit),
    Reset(GitReset),
    Push(GitPush),
}

impl Executable for GitCommand {
    fn into_command(self) -> Command {
        match self {
            Self::Commit(c) => c.into_command(),
            Self::Reset(r) => r.into_command(),
            Self::Push(p) => p.into_command(),
        }
    }
}
```

Exhaustive matching ensures all subcommands are handled.

### Crates Worth Studying

| Crate            | What it does                                              | Why study it                                             |
| ---------------- | --------------------------------------------------------- | -------------------------------------------------------- |
| `duct`           | Composable command pipelines (piping, redirection)        | Builder composition, error-by-default, `cmd!` macro      |
| `xshell`         | Ergonomic shell scripting with compile-time parsed `cmd!` | Shell-as-stateful-object, injection-safe by construction |
| `docker-wrapper` | 80+ Docker commands as typed builder structs              | Real-world `Executable` trait pattern at scale           |
| `assert_cmd`     | Testing CLI programs                                      | Builder for constructing + asserting on command outputs  |
| `typed-builder`  | Derive macro for compile-time checked builders            | Builder state encoded in generics                        |
| cargo internals  | `ProcessBuilder` in `cargo-util`                          | How Rust's own tooling wraps `Command`                   |

---

## Python Implementation

### Pydantic Approach (recommended)

```python
from __future__ import annotations
import subprocess
from pydantic import BaseModel, model_validator
from enum import Enum
from typing import Protocol


class ResetMode(str, Enum):
    """Mutually exclusive flags as enum."""
    SOFT = "--soft"
    MIXED = "--mixed"
    HARD = "--hard"


class GitCommit(BaseModel):
    message: str | None = None
    amend: bool = False
    sign: bool = False
    author: str | None = None
    allow_empty_message: bool = False

    @model_validator(mode="after")
    def validate_message(self) -> GitCommit:
        if not self.amend and not self.message and not self.allow_empty_message:
            raise ValueError("message is required unless --amend is used")
        return self

    def to_args(self) -> list[str]:
        args = ["git", "commit"]
        if self.message:
            args.extend(["-m", self.message])
        if self.amend:
            args.append("--amend")
        if self.sign:
            args.append("-S")
        if self.author:
            args.extend(["--author", self.author])
        return args


class GitReset(BaseModel):
    mode: ResetMode = ResetMode.MIXED
    ref: str = "HEAD"

    def to_args(self) -> list[str]:
        return ["git", "reset", self.mode.value, self.ref]
```

### Execution Protocol (equivalent of Rust trait)

```python
class Executable(Protocol):
    def to_args(self) -> list[str]: ...


def run(cmd: Executable, **kwargs) -> subprocess.CompletedProcess:
    return subprocess.run(cmd.to_args(), check=True, **kwargs)


def capture(cmd: Executable, **kwargs) -> str:
    result = subprocess.run(
        cmd.to_args(), check=True, capture_output=True, text=True, **kwargs
    )
    return result.stdout.strip()
```

### Usage

```python
commit = GitCommit(message="fix: something", sign=True)
run(commit)

output = capture(GitReset(mode=ResetMode.SOFT, ref="HEAD~3"))
```

### Dataclass Alternative (lighter weight)

```python
from dataclasses import dataclass


@dataclass(frozen=True)
class GitCommit:
    message: str
    amend: bool = False
    sign: bool = False

    def to_args(self) -> list[str]:
        args = ["git", "commit", "-m", self.message]
        if self.amend:
            args.append("--amend")
        if self.sign:
            args.append("-S")
        return args
```

Works fine, but you lose automatic validation. Use `__post_init__` for constraints.

### Pydantic vs Dataclass Decision

| Criteria                   | Pydantic                                          | Dataclass                       |
| -------------------------- | ------------------------------------------------- | ------------------------------- |
| Validation on construction | Built-in (`@field_validator`, `@model_validator`) | Manual (`__post_init__`)        |
| Runtime cost               | Higher (validation runs every time)               | Minimal                         |
| Serialization / debugging  | `.model_dump()` for free                          | Manual                          |
| Immutability               | `ConfigDict(frozen=True)`                         | `frozen=True`                   |
| Best for                   | External data boundaries, complex constraints     | Internal state, simple grouping |
| Adding methods             | Totally fine                                      | Totally fine                    |

**For CLI wrappers:** Pydantic is the better fit — you're modeling external constraints (mutually
exclusive flags, required combinations), and validators express that cleanly.

### Python Projects Using These Patterns

| Project         | Pattern                                                                    |
| --------------- | -------------------------------------------------------------------------- |
| GitPython       | `__getattr__` magic translates method calls + kwargs to git CLI args       |
| docker-py       | Typed Python classes modeling Docker domain, serialized to API/CLI calls   |
| Ansible modules | Each module = typed struct serialized into shell commands on remote hosts  |
| Plumbum         | Shell commands as composable objects with operator overloading (`\|`, `>`) |
| Invoke / Fabric | Task execution with typed context objects + connection management          |

---

## Anti-Patterns to Avoid

**Stringly-typed everything:**

```rust
// BAD: flags as scattered string args, no validation
fn git_commit(args: &[&str]) { ... }
```

**Baking execution into the builder:**

```rust
// BAD: caller can't choose how to run it
impl GitCommit {
    pub fn run(self) -> Result<()> { // locks you into one execution mode
        self.into_command().status()?;
        Ok(())
    }
}
```

**Two bools for mutually exclusive options:**

```rust
// BAD: allows both soft=true AND hard=true
pub struct GitReset {
    soft: bool,
    hard: bool,
}

// GOOD: enum makes invalid state unrepresentable
pub enum ResetMode { Soft, Mixed, Hard }
```

**Leaking raw `Output` to the rest of the app:**

```python
# BAD: callers deal with raw bytes, exit codes, stderr
def git_log() -> subprocess.CompletedProcess: ...

# GOOD: parse at the boundary, return domain types
def git_log() -> list[Commit]: ...
```

---

## Testing Strategy

**Rust:**

- Use `assert_cmd` to test the full roundtrip (build -> execute -> assert).
- Snapshot the generated `Command` args before executing (inspect without side effects).

**Python:**

- Test `to_args()` output directly — it's just a pure function returning `list[str]`.
- Mock `subprocess.run` at the execution boundary.

```python
def test_git_commit_args():
    cmd = GitCommit(message="fix: bug", sign=True, amend=True)
    assert cmd.to_args() == ["git", "commit", "-m", "fix: bug", "--amend", "-S"]

def test_git_commit_validation():
    with pytest.raises(ValueError):
        GitCommit()  # no message, no amend — should fail
```

```rust
#[test]
fn test_git_commit_args() {
    let cmd = GitCommit::new("fix: bug").sign().amend();
    let command = cmd.into_command();
    let args: Vec<&OsStr> = command.get_args().collect();
    assert_eq!(args, &["commit", "-m", "fix: bug", "--amend", "-S"]);
}
```
