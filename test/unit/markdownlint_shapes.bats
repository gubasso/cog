#!/usr/bin/env bats
#
# Static assertions over the MD043 heading-shape wiring.
#
# `MD043` takes one ordered heading array and markdownlint has no per-glob rule
# configuration, so each fixed shape carries its array in its own file under
# .markdownlint/ and one `md-*` hook entry chooses the documents it applies to.
# Two failure modes in that wiring are silent — the hooks keep reporting success
# while nothing is gated — which is why they are asserted here rather than left
# to a comment:
#
#   - A project .markdownlint-cli2.jsonc is discovered for the working directory
#     and merged OVER the `--config` base, so naming MD043 there at any value
#     (`false` included) switches off every shape.
#   - A shape config no hook entry names is decoration.
#
# The mechanism is documented in skill-refs/docs-design/10-lean-markdown.md.

setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
  SHAPE_DIR="${REPO_ROOT}/.markdownlint"
  HOOKS="${REPO_ROOT}/.pre-commit-config.yaml"
}

# Every .markdownlint-cli2.jsonc that is NOT a shape config: this repo's own
# project config plus the payloads shipped to bootstrapped projects. Each is
# discovered by directory and merges over any `--config` base.
_project_configs() {
  find "$REPO_ROOT" -name '.markdownlint-cli2.jsonc' -type f \
    -not -path '*/.markdownlint/*' -not -path '*/.git/*' | sort
}

_shape_configs() {
  find "$SHAPE_DIR" -name '*.markdownlint-cli2.jsonc' -type f | sort
}

# JSONC line comments are prose about the rule, not configuration, so a
# commented mention stays legal.
_uncommented() {
  sed 's#//.*##' "$1"
}

@test "no project markdownlint config names MD043" {
  local f bad=()
  while read -r f; do
    _uncommented "$f" | grep -q '"MD043"' && bad+=("${f#"$REPO_ROOT"/}")
  done < <(_project_configs)
  [ ${#bad[@]} -eq 0 ] || {
    echo "MD043 in a project config silently overrides every shape:"$'\n'"${bad[*]}" >&2
    return 1
  }
}

@test "every shape config supplies an MD043 headings array" {
  # MD043 is inert without one, so a shape config missing the array gates
  # nothing while looking like it does.
  local f bad=()
  while read -r f; do
    _uncommented "$f" | tr -d '[:space:]' | grep -q '"MD043":{"headings":\[' \
      || bad+=("${f#"$REPO_ROOT"/}")
  done < <(_shape_configs)
  [ ${#bad[@]} -eq 0 ] || {
    echo "shape config without an MD043 headings array:"$'\n'"${bad[*]}" >&2
    return 1
  }
}

@test "every shape config is applied by a hook entry" {
  local f rel bad=()
  while read -r f; do
    rel="${f#"$REPO_ROOT"/}"
    grep -qF -- "'--config', '$rel'" "$HOOKS" || bad+=("$rel")
  done < <(_shape_configs)
  [ ${#bad[@]} -eq 0 ] || {
    echo "shape config no hook entry names (the array is decoration):"$'\n'"${bad[*]}" >&2
    return 1
  }
}

@test "every hook --config target exists" {
  local rel bad=()
  while read -r rel; do
    [ -f "$REPO_ROOT/$rel" ] || bad+=("$rel")
  done < <(grep -o "'--config', '\.markdownlint/[^']*'" "$HOOKS" | sed "s/.*, '//;s/'$//")
  [ ${#bad[@]} -eq 0 ] || {
    echo "hook names a shape config that does not exist:"$'\n'"${bad[*]}" >&2
    return 1
  }
}
