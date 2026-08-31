# Bash completion for cog.
#
# The command list is static and mirrors:
#   find lib/commands -maxdepth 1 -name 'cmd_*.sh' | sort | sed 's#.*/cmd_##; s#\.sh$##; s#_#-#g'
# Per-command option completion is intentionally deferred because command
# metadata currently exposes command names and desc sentinels, not option specs.

_cog() {
  local cur prev word
  local subcommand_seen=false
  local -a global_flags=(
    -h
    --help
    -V
    --version
    --json
    --dry-run
    --print-config
    -v
    -vv
    -vvv
  )
  local -a commands=(
    assess-input
    bootstrap-audit
    bootstrap-template-review
    cargo-detect
    cargo-publish-apply
    cargo-publish-check
    cargo-publish-detect
    cargo-scaffold-apply
    ci-apply
    ci-detect
    classify-project
    claude-runner
    claudemd-audit
    codex-runner
    cog-skill-creator-scaffold
    cog-skill-creator-validate
    context-brief
    doctor
    editorconfig-apply
    editorconfig-detect
    executor
    executor-prex-parse-args
    gate
    gc-classify-failure
    gc-commit
    gc-commit-lint
    gc-commit-parse
    gc-loop-progress
    gc-plan
    gc-push
    gc-stage
    git-identity
    gitignore-apply
    gitignore-detect
    governance-apply
    governance-detect
    help
    hook-guard
    init
    installer-apply
    installer-detect
    jira-ticket-creator
    license-apply
    lint-codex-wrapper
    lock
    longrun
    msg
    nix-devshell-apply
    nix-devshell-detect
    noop
    osc-preflight
    osc-probe-binary
    plan-doc
    plan-gate
    plan-multi-setup
    plan-review
    plan-slug
    plugin
    precommit-apply-template
    precommit-detect
    precommit-run
    precommit-spell-select
    preflight
    print-config
    readme-apply
    require
    research-shelf
    review-comment
    review-init
    review-loop-input
    review-loop-progress
    review-loop-summary
    review-normalize-findings
    review-plan-multi-setup
    review-scope
    review-tech-scope
    review-validate-findings
    rundir
    skill-class
    skill-lint
    skill-refs
    suckless-apply
    suckless-conflicts
    suckless-preflight
    taskrunner-apply
    taskrunner-detect
    test-review-discover
    test-review-lint
    test-review-manifest
    tracking-scan
  )

  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD - 1]}"

  for word in "${COMP_WORDS[@]:1:COMP_CWORD-1}"; do
    [[ $word == -- ]] && break
    [[ $word == -* ]] && continue
    subcommand_seen=true
    break
  done

  if [[ $cur == -* ]]; then
    COMPREPLY=($(compgen -W "${global_flags[*]}" -- "$cur"))
    return 0
  fi

  if [[ $subcommand_seen == false ]]; then
    # Third-party cog-* plugins, appended at runtime and never written into the
    # static array above: help_snapshots.bats asserts that array equals
    # lib/commands/ exactly. Failure is silent by design — a missing, slow, or
    # broken cog must not break first-party completion.
    #
    # The hard time bound is the load-bearing half. Enumeration stats every
    # $PATH directory, so a stale network mount or an unresponsive filesystem
    # hangs it, and `|| true` only catches a command that eventually returns —
    # it cannot bound one that never does. Without the timeout, pressing Tab
    # would block the user's shell instead of quietly offering the first-party
    # names, which is what the reference promises.
    local -a plugin_names=()
    mapfile -t plugin_names < <(timeout 1 cog plugin list --names 2>/dev/null || true)
    ((${#plugin_names[@]})) && commands+=("${plugin_names[@]}")
    COMPREPLY=($(compgen -W "${commands[*]}" -- "$cur"))
    return 0
  fi

  case "$prev" in
    help)
      COMPREPLY=($(compgen -W "${commands[*]}" -- "$cur"))
      ;;
    *)
      COMPREPLY=($(compgen -W "--help ${global_flags[*]}" -- "$cur"))
      ;;
  esac
  return 0
}

complete -F _cog cog
