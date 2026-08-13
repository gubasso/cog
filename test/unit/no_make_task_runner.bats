setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
}

# `just` is the only task runner cog detects, deploys, or wires (ADR-0028).
#
# Two narrow exceptions survive, because neither is cog choosing a task runner —
# both invoke a foreign tree's own hand-written build system, which cog cannot
# replace:
#
#   - the suckless commands, which build dwm/st/dmenu with `make clean && make`
#   - the C pre-commit template's build hook and the C editorconfig tab rule
#
# `.implementation-plans/` is excluded wholesale: it is a machine queue of past
# rounds, and rewriting settled history there would be meaningless.
#
# Anything else matching a make-as-task-runner pattern is a leftover. This test
# is what keeps the migration from silently regressing.
_allowlisted() {
  case "$1" in
    lib/commands/cmd_suckless_*.sh) return 0 ;;
    skills/*/suckless-patcher/SKILL.md) return 0 ;;
    skill-refs/tools/suckless/*) return 0 ;;
    skill-refs/templates/pre-commit/c/.pre-commit-config.yaml) return 0 ;;
    skill-refs/templates/editorconfig/c/.editorconfig) return 0 ;;
    test/integration/cmd_suckless_*.bats) return 0 ;;
    test/unit/no_make_task_runner.bats) return 0 ;;
    docs/decisions/ADR-0028-*.md) return 0 ;;
    # Foreign-tree fixtures assert that a stray Makefile changes nothing.
    test/integration/cmd_taskrunner_*.bats) return 0 ;;
    test/unit/cmd_bootstrap_audit.bats) return 0 ;;
    *) return 1 ;;
  esac
}

@test "no make-as-task-runner references survive outside the foreign-build allowlist" {
  local repo_root file
  repo_root="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"

  local -a offenders=()
  while IFS= read -r file; do
    _allowlisted "$file" && continue
    offenders+=("$file")
  done < <(
    cd "$repo_root" && git grep -lEI \
      'Makefile|GNUmakefile|\.PHONY|\bgmake\b|\bmake (install|test|lint|build|clean)\b' \
      -- . ':(exclude).implementation-plans' 2>/dev/null || true
  )

  if [ ${#offenders[@]} -ne 0 ]; then
    printf 'make leftovers found in:\n' >&2
    printf '  %s\n' "${offenders[@]}" >&2
    return 1
  fi
}

@test "the make task-runner template is gone" {
  local repo_root
  repo_root="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"

  [ ! -e "$repo_root/skill-refs/templates/taskrunner/make" ]
  [ -f "$repo_root/skill-refs/templates/taskrunner/just/justfile" ]
}
