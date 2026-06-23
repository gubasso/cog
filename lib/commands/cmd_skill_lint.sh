# shellcheck shell=bash
: 'desc: Lint SKILL.md files against the skill/script boundary.'

__cog_skill_lint_usage() {
  cog::fn::ui_data "Usage: cog skill-lint [SKILL.md ...]"
}

__cog_skill_lint_repo_root() {
  if [[ -n ${LIB_DIR:-} ]]; then
    (cd "${LIB_DIR}/.." && pwd -P)
  else
    pwd -P
  fi
}

__cog_skill_lint_add_default_files() {
  local root="$1" path
  while IFS= read -r path; do
    [[ -n $path ]] && printf '%s\n' "$path"
  done < <(find "$root/skills/claude" "$root/skills/codex" "$root/.claude/skills" -mindepth 2 -maxdepth 2 -type f -name 'SKILL.md' -print 2>/dev/null | sort)
}

# Runtime skill-refs markdown (everything under skill-refs/ except the
# templates/ deploy payload) is scanned for the self-containment golden rules.
__cog_skill_lint_add_default_skill_refs() {
  local root="$1" path
  while IFS= read -r path; do
    [[ -n $path ]] && printf '%s\n' "$path"
  done < <(find "$root/skill-refs" -type f -name '*.md' -not -path "$root/skill-refs/templates/*" -print 2>/dev/null | sort)
}

__cog_skill_lint_finding() {
  local file="$1" line="$2" rule="$3" message="$4" fix="$5"
  printf '%s:%s: %s: %s; fix: %s\n' "$file" "$line" "$rule" "$message" "$fix" >&2
}

__cog_skill_lint_has_unknown_keys() {
  local file="$1" runtime="$2" unknown key failed=0
  unknown="$(cog::fn::skill::unknown_frontmatter_keys_json "$file" "$runtime")"
  while IFS= read -r key; do
    [[ -n $key ]] || continue
    __cog_skill_lint_finding "$file" 1 "frontmatter" "unknown key '${key}'" "remove it or add it to the runtime allowlist"
    failed=1
  done < <(jq -r '.[]' <<<"$unknown")
  return "$failed"
}

__cog_skill_lint_check_structure() {
  local file="$1" runtime parent name line_count emojis fences line failed=0

  runtime="$(cog::fn::skill::runtime_for_path "$file")"
  if [[ -z $runtime ]]; then
    __cog_skill_lint_finding "$file" 1 "path" "could not determine skill runtime" "place SKILL.md under skills/claude, skills/codex, or .claude/skills"
    failed=1
  fi

  if ! cog::fn::skill::has_frontmatter "$file"; then
    __cog_skill_lint_finding "$file" 1 "frontmatter" "missing or incomplete YAML frontmatter delimiters" "start SKILL.md with --- and close the frontmatter with ---"
    failed=1
  fi

  name="$(cog::fn::skill::frontmatter_name "$file")"
  if [[ -z $name ]]; then
    __cog_skill_lint_finding "$file" 1 "frontmatter" "missing name" "add a name key matching the parent directory"
    failed=1
  elif ! cog::fn::skill::name_is_valid "$name"; then
    __cog_skill_lint_finding "$file" 1 "name" "invalid skill name '${name}'" "use ^[a-z0-9-]{1,64}$ and avoid reserved names anthropic and claude"
    failed=1
  else
    parent="$(cog::fn::skill::parent_dir_name "$file")"
    if [[ $name != "$parent" ]]; then
      __cog_skill_lint_finding "$file" 1 "name" "name '${name}' does not match parent directory '${parent}'" "rename the directory or update frontmatter name"
      failed=1
    fi
  fi

  if [[ -n $runtime ]] && ! __cog_skill_lint_has_unknown_keys "$file" "$runtime"; then
    failed=1
  fi

  line_count="$(cog::fn::skill::line_count "$file")"
  if [[ $line_count -gt 500 ]]; then
    __cog_skill_lint_finding "$file" "$line_count" "line-count" "SKILL.md exceeds 500 lines" "split references or shorten the skill body"
    failed=1
  fi

  emojis="$(cog::fn::skill::emoji_lines_json "$file")"
  while IFS= read -r line; do
    [[ -n $line ]] || continue
    __cog_skill_lint_finding "$file" "$line" "emoji" "emoji character present" "remove emoji characters from skill instructions"
    failed=1
  done < <(jq -r '.[]' <<<"$emojis")

  fences="$(cog::fn::skill::untagged_fence_lines_json "$file")"
  while IFS= read -r line; do
    [[ -n $line ]] || continue
    __cog_skill_lint_finding "$file" "$line" "fence" "code fence has no language tag" "add a language tag such as bash, markdown, yaml, or text"
    failed=1
  done < <(jq -r '.[]' <<<"$fences")

  if [[ $runtime == claude ]] && ! cog::fn::skill::has_trigger_tests "$file"; then
    __cog_skill_lint_finding "$file" 1 "trigger-tests" "missing trigger-tests comment" "add an HTML trigger-tests comment near the frontmatter"
    failed=1
  fi

  return "$failed"
}

__cog_skill_lint_check_plan_gate() {
  # Plan-emitting skills write a plan to disk and must not run under Claude Code
  # plan mode (read-only). Detection is probabilistic and lives in skill prose
  # (the gate stanza); this structural check only verifies the stanza is present.
  # Claude runtime only -- Codex has no Claude plan mode.
  local file="$1" runtime failed=0
  runtime="$(cog::fn::skill::runtime_for_path "$file")"
  [[ $runtime == claude ]] || return 0
  if cog::fn::skill::is_plan_emitter "$file" && ! cog::fn::skill::has_plan_mode_gate "$file"; then
    __cog_skill_lint_finding "$file" 1 "plan-mode-gate" "plan-emitter skill missing plan-mode gate" "add a Phase 0 plan-mode gate marked with <!-- cog-plan-mode-gate -->"
    failed=1
  fi
  return "$failed"
}

__cog_skill_lint_check_prefix_taxonomy() {
  # Prefix taxonomy is a hard-fail structural contract for Claude skills with
  # governed declared intent.
  local file="$1" runtime name class expected=""

  runtime="$(cog::fn::skill::runtime_for_path "$file")"
  [[ $runtime == claude ]] || return 0

  name="$(cog::fn::skill::frontmatter_name "$file")"
  class="$(cog::fn::skill::classify_prefix "$name")"

  if cog::fn::skill::is_plan_reviewer_intent "$file"; then
    expected="review-plan"
  elif cog::fn::skill::is_executor_intent "$file"; then
    expected="executor"
  elif cog::fn::skill::is_plan_emitter "$file"; then
    expected="plan"
  else
    return 0
  fi

  [[ $class == "$expected" ]] && return 0

  __cog_skill_lint_finding \
    "$file" 1 "skill-prefix-taxonomy" \
    "skill intent '${expected}' does not match name prefix class '${class}'" \
    "rename the skill to '${expected}-*'"
  return 1
}

__cog_skill_lint_check_source_paths() {
  # Runtime skill files must not reference another skill's source-tree path
  # (e.g. skills/claude/<name>/SKILL.md or the stale Codex twin shape
  # codex-session/.agents/skills/<name>/SKILL.md). Such source-repo meta has no
  # meaning in the end-user runtime; reference the skill by its runtime name or
  # move the meta to docs/. Authoring placeholders (skills/claude/<name>/SKILL.md
  # with a literal <name>) and runtime-installed delegation paths
  # ($HOME/.claude/skills/... or project-local .claude/skills/...) are not
  # matched: the regex anchors to a concrete claude/codex source segment and a
  # real skill name. See docs/decisions/0019-lean-positive-skill-prose.md.
  local file="$1"
  local line line_no=0 failed=0 in_frontmatter=false frontmatter_done=false in_fence=false
  local fence_re='^[[:space:]]*```+'
  local src_re='(skills/(claude|codex)|codex-session/\.agents/skills)/[a-z0-9-]+/SKILL\.md'

  # shellcheck disable=SC2094
  while IFS= read -r line || [[ -n $line ]]; do
    line_no=$((line_no + 1))

    if [[ $line_no -eq 1 && $line == "---" ]]; then
      in_frontmatter=true
      continue
    fi
    if [[ $in_frontmatter == true ]]; then
      if [[ $line == "---" ]]; then
        in_frontmatter=false
        frontmatter_done=true
      fi
      continue
    fi
    [[ $frontmatter_done == false ]] && continue

    if [[ $line =~ $fence_re ]]; then
      if [[ $in_fence == true ]]; then in_fence=false; else in_fence=true; fi
      continue
    fi
    [[ $in_fence == true ]] && continue

    if [[ $line =~ $src_re ]]; then
      __cog_skill_lint_finding "$file" "$line_no" "skill-source-path-reference" \
        "source-repo skill path reference in runtime skill body" \
        "reference the skill by its runtime name, or move source-repo meta to docs/"
      failed=1
    fi
  done <"$file"

  return "$failed"
}

__cog_skill_lint_check_forbidden_runtime_refs() {
  local file="$1" runtime failed=0
  local line line_no=0 in_frontmatter=false frontmatter_done=false
  runtime="$(cog::fn::skill::runtime_for_path "$file")"
  [[ -n $runtime ]] || return 0

  # shellcheck disable=SC2094
  while IFS= read -r line || [[ -n $line ]]; do
    line_no=$((line_no + 1))

    if [[ $line_no -eq 1 && $line == "---" ]]; then
      in_frontmatter=true
      continue
    fi
    if [[ $in_frontmatter == true ]]; then
      if [[ $line == "---" ]]; then
        in_frontmatter=false
        frontmatter_done=true
      fi
      continue
    fi
    [[ $frontmatter_done == false ]] && continue

    if [[ $line == *"codex-conventions.md"* ]]; then
      __cog_skill_lint_finding "$file" "$line_no" "skill-codex-conventions-reference" \
        "runtime skill references codex-conventions.md" \
        "use the cog codex-runner command surface instead"
      failed=1
    fi
    if [[ $line == *"DOCS_NOTES_REPO"* ]]; then
      __cog_skill_lint_finding "$file" "$line_no" "skill-docs-notes-repo-reference" \
        "runtime skill references DOCS_NOTES_REPO" \
        "import load-bearing references to skill-refs and resolve them with cog skill-refs path"
      failed=1
    fi
  done <"$file"

  return "$failed"
}

# A runtime skill-refs file is any file under skill-refs/ that is loaded by a
# skill at runtime via `cog skill-refs path`. The templates/ subtree is a
# deploy payload copied into user projects, not a runtime ref, so it is exempt.
__cog_skill_lint_is_skill_refs_runtime() {
  local file="$1"
  [[ $file == *"skill-refs/"* ]] || return 1
  [[ $file == *"skill-refs/templates/"* ]] && return 1
  return 0
}

# Runtime skill-refs are surfaced to skills (e.g. review-tech-scope feeds
# code-review guides to review-lean), so the same self-containment golden
# rules that bind SKILL.md bodies bind the refs they load. Scan the whole file;
# refs carry no frontmatter to skip.
__cog_skill_lint_check_skill_refs_forbidden() {
  local file="$1" failed=0 line line_no=0
  # shellcheck disable=SC2094
  while IFS= read -r line || [[ -n $line ]]; do
    line_no=$((line_no + 1))
    if [[ $line == *"codex-conventions.md"* ]]; then
      __cog_skill_lint_finding "$file" "$line_no" "skill-refs-codex-conventions-reference" \
        "runtime skill-refs references codex-conventions.md" \
        "describe the behavior or point to the cog codex-runner command surface instead"
      failed=1
    fi
    if [[ $line == *"DOCS_NOTES_REPO"* ]]; then
      __cog_skill_lint_finding "$file" "$line_no" "skill-refs-docs-notes-repo-reference" \
        "runtime skill-refs references DOCS_NOTES_REPO" \
        "import the reference into skill-refs and resolve it with cog skill-refs path"
      failed=1
    fi
  done <"$file"
  return "$failed"
}

__cog_skill_lint_is_cog_extraction() {
  local line="$1"
  [[ $line =~ ^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=\"\$\(cog[[:space:]].*\|[[:space:]]*(sed[[:space:]]+-n|cut[[:space:]]|jq[[:space:]]+-r) ]]
}

__cog_skill_lint_is_simple_assignment() {
  local line="$1"
  [[ $line =~ ^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=\"?\$\{?[A-Za-z_][A-Za-z0-9_]*(:-[^}]*)?\}?\"?[[:space:]]*$ ]]
}

__cog_skill_lint_scan_premise_file() {
  local file="$1"
  local line line_no=0 in_shell=false fence_start=0 pending_allow=false block_allow=false failed=0
  local pending_while_line=0 pending_while_body="" i
  local -a deferred_while_lines=() deferred_while_bodies=()
  local open_re='^[[:space:]]*```+[[:space:]]*(bash|sh|shell)([[:space:]]|$)'
  local any_open_re='^[[:space:]]*```+'
  local close_re='^[[:space:]]*```+[[:space:]]*$'
  local allow_re='^[[:space:]]*<!--[[:space:]]*cog-skill-lint:[[:space:]]*allow-inline-shell[[:space:]][^[:space:]][^>]*-->[[:space:]]*$'

  # shellcheck disable=SC2094
  while IFS= read -r line || [[ -n $line ]]; do
    line_no=$((line_no + 1))

    if [[ $in_shell == false ]]; then
      if [[ $line =~ $allow_re ]]; then
        pending_allow=true
        continue
      fi
      if [[ $line =~ $open_re ]]; then
        in_shell=true
        fence_start="$line_no"
        block_allow="$pending_allow"
        pending_allow=false
        pending_while_line=0
        pending_while_body=""
        deferred_while_lines=()
        deferred_while_bodies=()
        continue
      fi
      if [[ $line =~ $any_open_re ]]; then
        pending_allow=false
      fi
      continue
    fi

    if [[ $line =~ $close_re ]]; then
      in_shell=false
      # Flush any still-open deferred `while ... read -r` loop, then resolve each
      # deferred loop against ITS OWN body (not the whole block): a loop whose body
      # never appends to an array (`arr+=(...)`) is not an argv builder and is flagged.
      if [[ $pending_while_line -ne 0 ]]; then
        deferred_while_lines+=("$pending_while_line")
        deferred_while_bodies+=("$pending_while_body")
        pending_while_line=0
        pending_while_body=""
      fi
      for i in "${!deferred_while_lines[@]}"; do
        if [[ ${deferred_while_bodies[i]} != *"+=("* ]]; then
          __cog_skill_lint_finding "$file" "${deferred_while_lines[i]}" "premise" "while loop in shell fence" "extract deterministic iteration into a cog subcommand"
          failed=1
        fi
      done
      deferred_while_lines=()
      deferred_while_bodies=()
      continue
    fi

    # Accumulate the body of the currently deferred while loop, so its argv-builder
    # exemption is judged on its own lines rather than the entire block. The body is
    # bounded at the loop's own `done`: a trailing array append AFTER the loop ends
    # must not absolve a real-work loop.
    if [[ $pending_while_line -ne 0 ]]; then
      pending_while_body+="${line}"$'\n'
      if [[ $line =~ ^[[:space:]]*done([[:space:]]|\<|$) ]]; then
        deferred_while_lines+=("$pending_while_line")
        deferred_while_bodies+=("$pending_while_body")
        pending_while_line=0
        pending_while_body=""
      fi
    fi
    [[ $block_allow == true ]] && continue
    [[ -z ${line//[[:space:]]/} || $line =~ ^[[:space:]]*# ]] && continue

    if [[ $line =~ ^[[:space:]]*[A-Za-z_][A-Za-z0-9_:-]*[[:space:]]*\(\)[[:space:]]*\{ ]]; then
      __cog_skill_lint_finding "$file" "$line_no" "premise" "shell function definition in skill body" "extract deterministic shell into a cog subcommand"
      failed=1
      continue
    fi

    if [[ $line =~ ^[[:space:]]*for[[:space:]] ]]; then
      __cog_skill_lint_finding "$file" "$line_no" "premise" "for loop in shell fence" "extract deterministic iteration into a cog subcommand"
      failed=1
      continue
    fi

    if [[ $line =~ ^[[:space:]]*while[[:space:]] ]]; then
      # Defer judgment on `while ... read -r` argv-array builders: the `arr+=(...)`
      # body usually appears on a later line, so the exclusion is resolved at fence
      # close against THIS loop's own body (see close_re handler). Other while loops
      # flag now. Starting a new loop flushes the previous deferred loop.
      if [[ $pending_while_line -ne 0 ]]; then
        deferred_while_lines+=("$pending_while_line")
        deferred_while_bodies+=("$pending_while_body")
        pending_while_line=0
        pending_while_body=""
      fi
      if [[ $line =~ ^[[:space:]]*while[[:space:]]+IFS=.*read[[:space:]]+-r ]]; then
        pending_while_line="$line_no"
        # Seed with the header line so a single-line `while ...; do arr+=(...); done`
        # idiom is recognized as an argv builder.
        pending_while_body="${line}"$'\n'
        continue
      fi
      __cog_skill_lint_finding "$file" "$line_no" "premise" "while loop in shell fence" "extract deterministic iteration into a cog subcommand"
      failed=1
      continue
    fi

    if [[ $line =~ ^[[:space:]]*case[[:space:]] ]]; then
      if [[ $line =~ ^[[:space:]]*case[[:space:]]+\"?\$[A-Za-z_][A-Za-z0-9_]*\"?[[:space:]]+in ]]; then
        continue
      fi
      __cog_skill_lint_finding "$file" "$line_no" "premise" "case dispatch in shell fence" "extract deterministic dispatch into a cog subcommand"
      failed=1
      continue
    fi

    if [[ $line =~ (grep[[:space:]]+-[^|;&]*P|grep[[:space:]]+-[^|;&]*nP|awk[[:space:]]|sed[[:space:]]) ]]; then
      if __cog_skill_lint_is_cog_extraction "$line"; then
        continue
      fi
      if [[ $line =~ ^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*= || $line =~ ^[[:space:]]*\|[[:space:]]*(awk|sed|grep) ]]; then
        continue
      fi
      __cog_skill_lint_finding "$file" "$line_no" "premise" "text-processing command in shell fence" "extract deterministic parsing into a cog subcommand"
      failed=1
      continue
    fi

    if __cog_skill_lint_is_simple_assignment "$line"; then
      continue
    fi
  done <"$file"

  if [[ $in_shell == true && $block_allow != true ]]; then
    __cog_skill_lint_finding "$file" "$fence_start" "fence" "unterminated shell fence" "close the fenced code block"
    failed=1
  fi

  return "$failed"
}

__cog_skill_lint_is_orchestration_rule() {
  local rule="$1"
  case "$rule" in
    orchestration-removed-codex-foreground | orchestration-pretooluse-guarantee | orchestration-background-codex | orchestration-claude-p-recursion | orchestration-unlimited-depth)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

__cog_skill_lint_has_background_prohibition() {
  local line="${1,,}"
  [[ $line =~ never[[:space:]]+background ]] && return 0
  [[ $line =~ do[[:space:]]+not[[:space:]]+background ]] && return 0
  [[ $line =~ must[[:space:]]+not[[:space:]]+background ]] && return 0
  [[ $line =~ run_in_background.*(false|omitted) ]] && return 0
  return 1
}

__cog_skill_lint_emit_orchestration_finding() {
  local file="$1" line_no="$2" rule="$3"
  case "$rule" in
    orchestration-removed-codex-foreground)
      # shellcheck disable=SC2016
      __cog_skill_lint_finding "$file" "$line_no" "$rule" "removed codex-foreground hook reference" 'describe env-first no-backgrounding plus `cog preflight`; do not reference the removed hook'
      ;;
    orchestration-pretooluse-guarantee)
      # shellcheck disable=SC2016
      __cog_skill_lint_finding "$file" "$line_no" "$rule" "PreToolUse hook claimed as runtime no-backgrounding guarantee" 'say `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1` is the guarantee and `cog` asserts it fail-closed'
      ;;
    orchestration-background-codex)
      # shellcheck disable=SC2016
      __cog_skill_lint_finding "$file" "$line_no" "$rule" "instruction to background orchestration work" 'let cog own long runs as durable jobs: launch with `cog codex-runner run-exec --state`, then poll-and-classify with `cog codex-runner finalize --max-wall <secs>` (exit 0 ok, 1 failed, 75 still running); only ad-hoc shell backgrounding (`&`, `run_in_background: true`) is prohibited'
      ;;
    orchestration-claude-p-recursion)
      # shellcheck disable=SC2016
      __cog_skill_lint_finding "$file" "$line_no" "$rule" 'headless `claude -p` described as preferred recursion primitive' "use Skill-inline for same-context composition or Agent-delegate for isolation"
      ;;
    orchestration-unlimited-depth)
      __cog_skill_lint_finding "$file" "$line_no" "$rule" "unqualified unlimited foreground-subagent depth claim" "state the hard cap is five subagent levels below the main conversation"
      ;;
  esac
}

__cog_skill_lint_is_removed_hook_line() {
  # The unambiguous removed-hook tokens. These are real command/identifier
  # strings, not prose, so they are flagged even inside fenced code blocks
  # (a `cog hook-guard codex-foreground` command in a ```bash fence is exactly
  # the "no leftovers" leftover the rule must catch).
  local line="$1"
  [[ $line =~ cog[[:space:]]+hook-guard[[:space:]]+codex-foreground || $line =~ guard-codex-foreground || $line =~ codex-foreground ]]
}

__cog_skill_lint_orchestration_rule_for_line() {
  local line="$1" lower="${1,,}"

  if __cog_skill_lint_is_removed_hook_line "$line"; then
    printf '%s\n' "orchestration-removed-codex-foreground"
    return 0
  fi

  if { [[ $line =~ PreToolUse && $lower =~ guarantee ]] \
    || [[ $line =~ PreToolUse && $lower =~ no-background ]] \
    || [[ $line =~ PreToolUse && $lower =~ prevent.*background ]] \
    || [[ $lower =~ hook && $lower =~ guarantee && $lower =~ background ]]; }; then
    printf '%s\n' "orchestration-pretooluse-guarantee"
    return 0
  fi

  # cog-OWNED durable jobs are sanctioned. The agency distinction is the rule:
  # cog (not the model) detaches the process via setsid and owns its lifecycle
  # through a durable state file, so invoking the durable-job protocol is never
  # the banned "model backgrounds its own tool call". Only model-issued ad-hoc
  # backgrounding (`&`, `run_in_background: true`) stays flagged.
  local is_durable_job=false
  if [[ $lower =~ cog[[:space:]]+(longrun|codex-runner)[[:space:]]+(start|run-exec|run-resume|finalize|status|cancel) ]]; then
    is_durable_job=true
  fi

  if [[ $is_durable_job == false ]] && ! __cog_skill_lint_has_background_prohibition "$line"; then
    if { [[ $line =~ run_in_background.*true && $lower =~ (codex|orchestration|subagent|delegate) ]] \
      || [[ $lower =~ (^|[[:space:]\`[:punct:]])background[[:space:]]+(the[[:space:]]+|a[[:space:]]+|an[[:space:]]+|this[[:space:]]+|that[[:space:]]+)?(codex|orchestration|delegate|subagent) ]] \
      || [[ $lower =~ (^|[[:space:]\`[:punct:]])detach[[:space:]]+(the[[:space:]]+|a[[:space:]]+|an[[:space:]]+|this[[:space:]]+|that[[:space:]]+)?(codex|orchestration|delegate|subagent) ]]; }; then
      printf '%s\n' "orchestration-background-codex"
      return 0
    fi
  fi

  if { [[ $lower =~ headless[[:space:]]+\`?claude[[:space:]]+-p\`? && $lower =~ (preferred|use|primitive) ]] \
    || [[ $lower =~ claude[[:space:]]+-p && $lower =~ (recursion|delegate|subagent|process[[:space:]]+primitive|preferred) ]]; }; then
    printf '%s\n' "orchestration-claude-p-recursion"
    return 0
  fi

  if [[ ! $lower =~ depth.*not[[:space:]]+configurable ]]; then
    if [[ $lower =~ unlimited[[:space:]]+depth || $lower =~ nest.*unlimited || $lower =~ unbounded.*subagent || $lower =~ no[[:space:]]+depth[[:space:]]+limit ]]; then
      printf '%s\n' "orchestration-unlimited-depth"
      return 0
    fi
  fi

  return 1
}

__cog_skill_lint_scan_prose_file() {
  local file="$1"
  local line line_no=0 failed=0 in_frontmatter=false frontmatter_done=false in_fence=false
  local pending_allow_rule="" rule reason current_allow_rule
  local marker_re='^[[:space:]]*<!--[[:space:]]*cog-skill-lint:[[:space:]]*allow-orchestration-history[[:space:]]+([^[:space:]]+)[[:space:]]+([^>][^>]*)-->[[:space:]]*$'
  local fence_re='^[[:space:]]*```+'

  # shellcheck disable=SC2094
  while IFS= read -r line || [[ -n $line ]]; do
    line_no=$((line_no + 1))

    if [[ $line_no -eq 1 && $line == "---" ]]; then
      in_frontmatter=true
      continue
    fi
    if [[ $in_frontmatter == true ]]; then
      if [[ $line == "---" ]]; then
        in_frontmatter=false
        frontmatter_done=true
      fi
      continue
    fi
    [[ $frontmatter_done == false ]] && continue

    if [[ $line =~ $fence_re ]]; then
      if [[ $in_fence == true ]]; then in_fence=false; else in_fence=true; fi
      continue
    fi

    # Inside a fenced code block the prose rules (background/claude-p/depth)
    # are skipped to avoid flagging documented negative examples, but the
    # unambiguous removed-hook tokens are still flagged: a real stale command
    # most often lives in a ```bash fence, and the "no leftovers" guarantee
    # must reach there too. The allow-orchestration-history marker (which
    # precedes the fence) still suppresses it.
    if [[ $in_fence == true ]]; then
      current_allow_rule=""
      if [[ -n ${line//[[:space:]]/} && -n $pending_allow_rule ]]; then
        current_allow_rule="$pending_allow_rule"
        pending_allow_rule=""
      fi
      if __cog_skill_lint_is_removed_hook_line "$line"; then
        if [[ $current_allow_rule != "orchestration-removed-codex-foreground" ]]; then
          __cog_skill_lint_emit_orchestration_finding "$file" "$line_no" "orchestration-removed-codex-foreground"
          failed=1
        fi
      fi
      continue
    fi

    if [[ $line =~ $marker_re ]]; then
      rule="${BASH_REMATCH[1]}"
      reason="${BASH_REMATCH[2]}"
      if __cog_skill_lint_is_orchestration_rule "$rule" && [[ -n ${reason//[[:space:]]/} ]]; then
        pending_allow_rule="$rule"
      else
        pending_allow_rule=""
      fi
      continue
    fi

    current_allow_rule=""
    if [[ -n ${line//[[:space:]]/} && -n $pending_allow_rule ]]; then
      current_allow_rule="$pending_allow_rule"
      pending_allow_rule=""
    fi

    if rule="$(__cog_skill_lint_orchestration_rule_for_line "$line")"; then
      if [[ $rule == "$current_allow_rule" ]]; then
        continue
      fi
      __cog_skill_lint_emit_orchestration_finding "$file" "$line_no" "$rule"
      failed=1
    fi
  done <"$file"

  return "$failed"
}

# Consumer skill name -> space-separated producer names it must not name in prose.
__cog_skill_lint_producer_blind_producers() {
  case "$1" in
    runner-queue) printf '%s' "plan-writer plan-writer-multi" ;;
    review-findings) printf '%s' "review-code-deep review-lean review-loop" ;;
    *) printf '%s' "" ;;
  esac
}

# Returns 0 when $1 (a line) contains $2 (a producer name) as a complete
# skill-name token: letters, digits, underscore, and hyphen are token
# characters, so review-code-deep matches `review-code-deep` and /review-code-deep
# but not review-code-deeper or my-review-code-deep-wrapper.
__cog_skill_lint_line_has_producer_token() {
  local line="$1" producer="$2"
  local rest="$line" before="" idx after
  while [[ $rest == *"$producer"* ]]; do
    idx="${rest%%"$producer"*}"
    before="${idx: -1}"
    after="${rest:${#idx}+${#producer}:1}"
    if [[ ! $before =~ [A-Za-z0-9_-] && ! $after =~ [A-Za-z0-9_-] ]]; then
      return 0
    fi
    rest="${rest:${#idx}+${#producer}}"
  done
  return 1
}

# Producer-blindness: a mapped consumer skill must not name the producer of its
# structural input. The scan covers frontmatter description text and body prose
# (the review-findings leaks live partly in the folded description:), and only
# fenced code blocks are skipped. See docs/decisions/0026-consumer-skill-producer-blindness.md.
__cog_skill_lint_check_producer_blind() {
  local file="$1"
  local name producers
  name="$(cog::fn::skill::frontmatter_name "$file")"
  producers="$(__cog_skill_lint_producer_blind_producers "$name")"
  [[ -z $producers ]] && return 0

  local line line_no=0 failed=0 in_fence=false producer
  local fence_re='^[[:space:]]*```+'

  # shellcheck disable=SC2094
  while IFS= read -r line || [[ -n $line ]]; do
    line_no=$((line_no + 1))

    if [[ $line =~ $fence_re ]]; then
      if [[ $in_fence == true ]]; then in_fence=false; else in_fence=true; fi
      continue
    fi
    [[ $in_fence == true ]] && continue

    for producer in $producers; do
      if __cog_skill_lint_line_has_producer_token "$line" "$producer"; then
        __cog_skill_lint_finding "$file" "$line_no" "producer-blindness" \
          "names producer skill '${producer}'; a consumer must be blind to its input's producer" \
          "describe the structural input contract (e.g. .implementation-plans/ or the findings contract); do not name the producer skill"
        failed=1
      fi
    done
  done <"$file"

  return "$failed"
}

__cog_skill_lint_scan_file() {
  local file="$1" failed=0
  [[ -r $file && -f $file ]] || cog::fn::error_raise "InputUnreadable" "skill-lint input is not readable" "path: ${file}" "" "pass readable SKILL.md files"
  if __cog_skill_lint_is_skill_refs_runtime "$file"; then
    __cog_skill_lint_check_skill_refs_forbidden "$file"
    return $?
  fi
  if ! __cog_skill_lint_check_structure "$file"; then
    failed=1
  fi
  if ! __cog_skill_lint_check_plan_gate "$file"; then
    failed=1
  fi
  if ! __cog_skill_lint_check_prefix_taxonomy "$file"; then
    failed=1
  fi
  if ! __cog_skill_lint_check_source_paths "$file"; then
    failed=1
  fi
  if ! __cog_skill_lint_check_forbidden_runtime_refs "$file"; then
    failed=1
  fi
  if ! __cog_skill_lint_check_producer_blind "$file"; then
    failed=1
  fi
  if ! __cog_skill_lint_scan_premise_file "$file"; then
    failed=1
  fi
  if ! __cog_skill_lint_scan_prose_file "$file"; then
    failed=1
  fi
  return "$failed"
}

cog::cmd::skill_lint() {
  local repo_root file failed=0
  local -a files=()

  case "${1:-}" in
    -h | --help)
      __cog_skill_lint_usage
      return 0
      ;;
  esac

  if (($# > 0)); then
    files=("$@")
  else
    repo_root="$(__cog_skill_lint_repo_root)"
    while IFS= read -r file; do
      files+=("$file")
    done < <(__cog_skill_lint_add_default_files "$repo_root")
    while IFS= read -r file; do
      files+=("$file")
    done < <(__cog_skill_lint_add_default_skill_refs "$repo_root")
  fi

  for file in "${files[@]}"; do
    if ! __cog_skill_lint_scan_file "$file"; then
      failed=1
    fi
  done

  if [[ $failed -ne 0 ]]; then
    exit 1
  fi
  return 0
}
