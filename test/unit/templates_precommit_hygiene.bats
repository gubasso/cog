#!/usr/bin/env bats
#
# Static hygiene assertions over the shipped bootstrap templates.
#
# These are content assertions, not command tests: every rule here encodes a
# defect that was found in the wild after a project was bootstrapped from these
# templates, and each would otherwise be re-emitted into every new project.
# The rationale for each rule lives in
# skill-refs/pre-commit/hook-language-resolution.md.

setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
  PRECOMMIT_TEMPLATES="${REPO_ROOT}/skill-refs/templates/pre-commit"
  NIX_TEMPLATES="${REPO_ROOT}/skill-refs/templates/nix"
}

# All shipped pre-commit config fragments: the per-type headline configs plus
# the shared overlays that get appended into them.
_precommit_configs() {
  find "$PRECOMMIT_TEMPLATES" -name '*.yaml' -type f | sort
}

@test "no template pins the legacy 'ruff' hook id" {
  # Upstream renamed ruff -> ruff-check and marks bare `ruff` a legacy alias.
  run bash -c "grep -rn '^\s*- id: ruff\s*\$' '$PRECOMMIT_TEMPLATES' || true"
  assert_success
  [ -z "$output" ] || {
    echo "legacy 'ruff' id (use 'ruff-check'):"$'\n'"$output" >&2
    return 1
  }
}

@test "no ruff hook uses config-replacing --select" {
  # A CLI --select REPLACES the active rule selection from EVERY resolved config
  # file, so the project's own select stops applying and per-file-ignores for the
  # dropped rules become moot.
  run bash -c "grep -rn 'args:.*--select' '$PRECOMMIT_TEMPLATES' | grep -v -- '--extend-select' || true"
  assert_success
  [ -z "$output" ] || {
    echo "use --extend-select, not --select:"$'\n'"$output" >&2
    return 1
  }
}

@test "every typos hook overrides args (upstream default auto-fixes)" {
  # Upstream default is [--write-changes, --force-exclude]; overriding no args
  # inherits it, so a stanza documented "report-only" actually rewrites files.
  # The stanza runs to the next `- id:`/`- repo:`, not a fixed line window: a
  # load-bearing comment between the id and `args:` must not fail a valid config.
  local f bad=()
  while read -r f; do
    grep -q '^\s*- id: typos\s*$' "$f" || continue
    awk '
      /^[[:space:]]*- (id|repo):/ { if (inhook && !found) missing = 1; inhook = 0 }
      /^[[:space:]]*- id: typos[[:space:]]*$/ { inhook = 1; found = 0; next }
      inhook && /^[[:space:]]*args:/ { found = 1 }
      END { if (inhook && !found) missing = 1; exit(missing ? 1 : 0) }
    ' "$f" || bad+=("$f")
  done < <(_precommit_configs)
  [ ${#bad[@]} -eq 0 ] || {
    echo "typos hook without explicit args:"$'\n'"${bad[*]}" >&2
    return 1
  }
}

@test "one repo pins one rev across every template" {
  # Divergent revs for the same repo mean projects bootstrapped from different
  # types silently get different tool versions.
  run bash -c "
    grep -rhB8 '^\s*rev:' '$PRECOMMIT_TEMPLATES' |
      awk '/- repo:/ {repo=\$3} /rev:/ && repo {print repo, \$2}' |
      sort -u | awk '{print \$1}' | uniq -d"
  assert_success
  [ -z "$output" ] || {
    echo "repo pinned at multiple revs:"$'\n'"$output" >&2
    return 1
  }
}

@test "no nix .envrc claims plain 'use flake' is GC-unrooted" {
  # direnv's own use_flake passes --profile "$(direnv_layout_dir)/flake-profile",
  # and a Nix profile generation is a permanent GC root, so plain `use flake` is
  # rooted. A probe gating on nix_direnv_version would enforce a false
  # requirement in every generated project.
  local d bad=()
  for d in "$NIX_TEMPLATES"/*/; do
    [ -f "$d/.envrc" ] || continue
    grep -q 'nix_direnv_version' "$d/.envrc" && bad+=("$d.envrc")
  done
  [ ${#bad[@]} -eq 0 ] || {
    echo ".envrc asserting an obsolete nix-direnv GC-root requirement:"$'\n'"${bad[*]}" >&2
    return 1
  }
}

# Evaluate the python .envrc against a stubbed direnv stdlib. `log_error` is
# stubbed to print and return 0 — exactly what direnv's real implementation
# does — so a guard that merely logs cannot pass these tests.
_eval_python_envrc() {
  local venv_bin="$1"
  local stub="$BATS_TEST_TMPDIR/stdlib.sh"
  mkdir -p "$venv_bin"
  cat >"$stub" <<STUB
use() { :; }
watch_file() { :; }
log_status() { :; }
log_error() { echo "\$*" >&2; }
PATH_add() { PATH="\$1:\$PATH"; export PATH; }
poetry() { echo "$(dirname "$venv_bin")"; }
STUB
  run bash -c ". '$stub'; . '$NIX_TEMPLATES/python/.envrc'"
}

@test "python .envrc fails the environment when the venv shadows a devShell tool" {
  # PATH_add prepends, so a tool in both the venv and the devShell resolves to
  # the venv copy — fatal when that copy is a PyPI binary wheel on a Nix host.
  local bin="$BATS_TEST_TMPDIR/shadowed/bin"
  mkdir -p "$bin"
  printf '#!/bin/sh\nexit 0\n' >"$bin/dprint"
  chmod +x "$bin/dprint"
  _eval_python_envrc "$bin"
  assert_failure
  assert_output --partial 'shadows devShell-owned tools'
  assert_output --partial 'dprint'
}

@test "python .envrc loads cleanly when the venv shadows nothing" {
  _eval_python_envrc "$BATS_TEST_TMPDIR/clean/bin"
  assert_success
}

@test "every nix flake provides the language:system hook tools its projects get" {
  # `language: system` hooks get no environment and resolve off ambient PATH, so
  # each needs a named provider in the devShell. The check covers EVERY nix
  # template, not just python: the shared _nix and _markdown overlays append
  # `language: system` hooks to every project type, so a gap in any one flake
  # ships a hook that cannot run. Scoping this to a single pair is exactly how
  # four of five templates went unnoticed.
  local flake t entry tool bad=()
  for flake in "$NIX_TEMPLATES"/*/flake.nix; do
    t="$(basename "$(dirname "$flake")")"
    while read -r entry; do
      tool="${entry%% *}"
      # Package-manager front-ends resolve the real tool through the project's
      # own dependency tree (Poetry venv, node_modules), which is that manager's
      # job, not the devShell's. The front-end itself still needs a provider:
      # `npx` ships inside any nodejs derivation, so map it there.
      [ "$tool" = "poetry" ] && continue
      [ "$tool" = "npx" ] && tool="nodejs"
      grep -qE "pkgs\.${tool}[a-zA-Z0-9_]*\b" "$flake" || bad+=("$t:$tool")
    done < <(
      # Every type receives the shared overlays; a type's own config only exists
      # for the pre-commit types, so union whatever applies to this flake.
      cat "$PRECOMMIT_TEMPLATES/_nix/hook.pre-commit.yaml" \
        "$PRECOMMIT_TEMPLATES/_markdown/hook.pre-commit.yaml" \
        "$PRECOMMIT_TEMPLATES/$t/.pre-commit-config.yaml" 2>/dev/null \
        | grep -B3 'language: system' | grep 'entry:' | sed 's/.*entry: //' | sort -u
    )
  done
  [ ${#bad[@]} -eq 0 ] || {
    echo "language:system hook tool missing from its flake.nix:"$'\n'"${bad[*]}" >&2
    return 1
  }
}

@test "no template tells the user to install a hook tool outside the devShell" {
  # Policy: flake.nix + .envrc set up the environment; a `language: system` hook
  # relies on that and nothing else. Out-of-band install advice contradicts it
  # and rots the moment the flake gains a provider.
  run bash -c "grep -rnE 'cargo install dprint|must be on PATH \(' '$PRECOMMIT_TEMPLATES' || true"
  assert_success
  [ -z "$output" ] || {
    echo "out-of-band install advice (the devShell is the provider):"$'\n'"$output" >&2
    return 1
  }
}
