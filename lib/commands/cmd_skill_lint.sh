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

__cog_skill_lint_input_fidelity_required() {
  local name="$1" runtime="$2"
  case "${runtime}:${name}" in
    claude:plan-multi | \
      claude:plan-vetted | \
      claude:plan-builder-to-queue | \
      claude:review-plan-multi | \
      claude:review-loop | \
      claude:context-builder | \
      claude:ask | \
      claude:bootstrap | \
      claude:executor-greenfield-from-spec | \
      claude:executor-prex | \
      claude:executor-oneshot | \
      claude:executor-vetted | \
      claude:executor-oneshot-codex | \
      claude:plan-oneshot-codex | \
      codex:executor-oneshot)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

__cog_skill_lint_check_input_fidelity() {
  local file="$1" runtime name failed=0
  runtime="$(cog::fn::skill::runtime_for_path "$file")"
  [[ -n $runtime ]] || return 0
  name="$(cog::fn::skill::frontmatter_name "$file")"
  if __cog_skill_lint_input_fidelity_required "$name" "$runtime" \
    && ! cog::fn::skill::has_input_fidelity_marker "$file"; then
    __cog_skill_lint_finding "$file" 1 "input-fidelity" \
      "brief-building delegator missing input-fidelity marker" \
      "add <!-- cog-skill: input-fidelity --> and keep delegated input enrichment-only"
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
      __cog_skill_lint_finding "$file" "$line_no" "skill-external-repo-dependency" \
        "runtime skill takes a load-bearing dependency on an external/local docs repository" \
        "import load-bearing references to skill-refs and resolve them with cog skill-refs path"
      failed=1
    fi
  done <"$file"

  return "$failed"
}

# A run/scratch/temp/work directory built from a working-tree root: $(pwd),
# ${PWD}, $PWD, or a ./-relative or dotdir path assigned to a scratch-named
# variable, or an mkdir of a working-tree-rooted path. The canonical
# `cog rundir <prefix>` binding uses none of these, so it is not matched.
__cog_skill_lint_line_scratch_in_project() {
  local line="$1"
  local scratch_assign='(^|[[:space:]])(export[[:space:]]+)?(RUN|RUNDIR|RUN_DIR|SCRATCH|SCRATCH_DIR|TMP|TMPDIR|TEMP|TEMPDIR|WORK|WORKDIR|WORK_DIR)='
  # shellcheck disable=SC2016 # literal regex metacharacters for $(pwd)/${PWD}, not expansions
  local cwd_root='\$\(pwd\)|\$\{PWD\}|\$PWD'
  if [[ $line =~ $scratch_assign ]]; then
    [[ $line =~ ($cwd_root) ]] && return 0
    [[ $line =~ =\"?\.\/ ]] && return 0
    [[ $line =~ =\"?\.[a-zA-Z0-9_-] ]] && return 0
  fi
  if [[ $line =~ (^|[[:space:]])mkdir[[:space:]] ]]; then
    [[ $line =~ ($cwd_root) ]] && return 0
  fi
  return 1
}

__cog_skill_lint_check_scratch_in_project() {
  # A skill that needs scratch space obtains a run directory via `cog rundir
  # <prefix>`; scratch never lands in the project tree or CWD. This fails a
  # run/scratch/temp/work directory rooted in the working tree. The scan covers
  # fenced code blocks — the anti-pattern most often lives in a bash fence — and
  # skips only frontmatter. An inline
  # <!-- cog-skill-lint: allow-scratch-in-project <reason> --> on the preceding
  # nonblank line suppresses the next content line. See
  # docs/decisions/0061-rundir-scratch-artifact-convention.md.
  local file="$1"
  local line line_no=0 failed=0 in_frontmatter=false frontmatter_done=false suppress_next=false
  local allow_re='<!--[[:space:]]*cog-skill-lint:[[:space:]]*allow-scratch-in-project[[:space:]]+.+-->'
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

    # Fence delimiters and blank lines never consume a pending suppression, so a
    # marker placed immediately before a fence still suppresses the first
    # offending line inside it.
    [[ $line =~ $fence_re ]] && continue
    [[ -z ${line//[[:space:]]/} ]] && continue

    if [[ $line =~ $allow_re ]]; then
      suppress_next=true
      continue
    fi

    if __cog_skill_lint_line_scratch_in_project "$line"; then
      if [[ $suppress_next == true ]]; then
        suppress_next=false
        continue
      fi
      # shellcheck disable=SC2016 # literal Markdown backticks in the fix hint, not command substitution
      __cog_skill_lint_finding "$file" "$line_no" "scratch-in-project" \
        "scratch or run directory rooted in the project tree or CWD" \
        'obtain a run directory with `cog rundir <prefix>` and keep scratch under it'
      failed=1
      continue
    fi
    suppress_next=false
  done <"$file"

  return "$failed"
}

__cog_skill_lint_line_codex_relpath() {
  # Given a line inside a `cog codex-runner` invocation, return 0 when it passes
  # a write-artifact flag (--state/--output/--events/--stderr) a relative literal
  # path. Absolute (/…), variable ($…/${…}), home (~…), and angle-bracket
  # placeholder (<file>, <RUN_DIR>/…) tokens pass.
  local line="$1"
  local re='--(state|output|events|stderr)[[:space:]]+"?([^[:space:]"]+)'
  local rest="$line" path
  while [[ $rest =~ $re ]]; do
    path="${BASH_REMATCH[2]}"
    case "$path" in
      /* | '$'* | '~'* | '<'*) ;;
      *) return 0 ;;
    esac
    rest="${rest#*"${BASH_REMATCH[0]}"}"
  done
  return 1
}

__cog_skill_lint_line_output_tokens() {
  # Print each --output literal token on the line (quote-stripped). Angle-bracket
  # <placeholder> tokens are dropped, matching __cog_skill_lint_line_codex_relpath.
  local line="$1"
  local re='--output[[:space:]]+"?([^[:space:]"]+)'
  local rest="$line" path
  while [[ $rest =~ $re ]]; do
    path="${BASH_REMATCH[1]}"
    rest="${rest#*"${BASH_REMATCH[0]}"}"
    case "$path" in
      '<'*) continue ;;
    esac
    printf '%s\n' "$path"
  done
}

__cog_skill_lint_check_codex_output_collision() {
  # Codex overwrites the runner's --output (its --output-last-message) with its
  # closing message. When a prompt the same invocation launches also writes a
  # durable artifact to that exact path — an embedded `--output <path>` elsewhere
  # in the skill, e.g. `$plan-oneshot --output $RUN_DIR/prepared-plan.md` — the
  # closing message clobbers the artifact. Flag a literal --output token that
  # appears both on a `cog codex-runner` invocation and off it. Comparison is on
  # literal spelling (authored static text keeps $RUN_DIR unexpanded), fence-aware,
  # frontmatter-skipping, and honors an inline
  # <!-- cog-skill-lint: allow-codex-runner-output-collision <reason> --> on the
  # preceding nonblank line. The runtime guard in cog codex-runner catches the
  # resolved-path case; this rule catches the authored/unexpanded-variable case.
  # See docs/decisions/0079-codex-runner-output-collision-guard.md.
  local file="$1"
  local line line_no=0 failed=0 in_frontmatter=false frontmatter_done=false suppress_next=false in_codex_cmd=false cmd_suppressed=false tok
  local allow_re='<!--[[:space:]]*cog-skill-lint:[[:space:]]*allow-codex-runner-output-collision[[:space:]]+.+-->'
  local fence_re='^[[:space:]]*```+'
  local -a runner_tok=() runner_line=() runner_supp=() embedded_tok=()

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
      in_codex_cmd=false
      continue
    fi
    [[ -z ${line//[[:space:]]/} ]] && continue

    if [[ $line =~ $allow_re ]]; then
      suppress_next=true
      continue
    fi

    if [[ $line == *"codex-runner"* && $in_codex_cmd == false ]]; then
      in_codex_cmd=true
      cmd_suppressed=$suppress_next
    fi

    while IFS= read -r tok; do
      [[ -n $tok ]] || continue
      if [[ $in_codex_cmd == true ]]; then
        runner_tok+=("$tok")
        runner_line+=("$line_no")
        runner_supp+=("$cmd_suppressed")
      else
        embedded_tok+=("$tok")
      fi
    done < <(__cog_skill_lint_line_output_tokens "$line")

    # A line without a trailing backslash terminates the invocation.
    [[ $line != *\\ ]] && in_codex_cmd=false
    suppress_next=false
  done <"$file"

  local i j
  for i in "${!runner_tok[@]}"; do
    [[ ${runner_supp[$i]} == true ]] && continue
    for j in "${!embedded_tok[@]}"; do
      if [[ ${runner_tok[$i]} == "${embedded_tok[$j]}" ]]; then
        # shellcheck disable=SC2016 # literal $RUN_DIR in the fix hint, not command substitution
        __cog_skill_lint_finding "$file" "${runner_line[$i]}" "codex-runner-output-collision" \
          "codex-runner --output reuses a path a prompt artifact-write also targets (${runner_tok[$i]})" \
          'route the last-message capture to a distinct $RUN_DIR/<label>-codex-output.md'
        failed=1
        break
      fi
    done
  done

  return "$failed"
}

__cog_skill_lint_check_codex_abs_artifact() {
  # A `cog codex-runner` durable job launches from the project repo, so a
  # relative --state/--output/--events/--stderr resolves against the project tree
  # and scatters artifacts into it. Flag a relative literal artifact path inside a
  # codex-runner invocation (which continues across backslash-continued lines);
  # absolute, $variable, and ~ paths pass. The scan covers fenced code blocks,
  # skips frontmatter, and honors an inline
  # <!-- cog-skill-lint: allow-codex-runner-abs-artifact-path <reason> --> on the
  # preceding nonblank line. See
  # docs/decisions/0061-rundir-scratch-artifact-convention.md.
  local file="$1"
  local line line_no=0 failed=0 in_frontmatter=false frontmatter_done=false suppress_next=false in_codex_cmd=false
  local allow_re='<!--[[:space:]]*cog-skill-lint:[[:space:]]*allow-codex-runner-abs-artifact-path[[:space:]]+.+-->'
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

    # A fence delimiter ends any open invocation but never consumes a pending
    # suppression, so a marker before a fence still suppresses the first line in it.
    if [[ $line =~ $fence_re ]]; then
      in_codex_cmd=false
      continue
    fi
    [[ -z ${line//[[:space:]]/} ]] && continue

    if [[ $line =~ $allow_re ]]; then
      suppress_next=true
      continue
    fi

    [[ $line == *"codex-runner"* ]] && in_codex_cmd=true

    if [[ $in_codex_cmd == true ]] && __cog_skill_lint_line_codex_relpath "$line"; then
      if [[ $suppress_next == true ]]; then
        suppress_next=false
      else
        # shellcheck disable=SC2016 # literal Markdown backticks in the fix hint, not command substitution
        __cog_skill_lint_finding "$file" "$line_no" "codex-runner-abs-artifact-path" \
          "relative codex-runner artifact path resolves against the project tree" \
          'pass an absolute path from `cog rundir <prefix>` (e.g. $RUN_DIR/<file>) to --state/--output/--events/--stderr'
        failed=1
      fi
    fi

    # A line without a trailing backslash terminates the invocation.
    [[ $line != *\\ ]] && in_codex_cmd=false
    suppress_next=false
  done <"$file"

  return "$failed"
}

__cog_skill_lint_line_has_stage_identifier() {
  local line="$1"
  [[ $line =~ stage[0-9]+[-_.] ]] && return 0
  [[ $line =~ --stage[0-9]+ ]] && return 0
  [[ $line =~ stage[0-9]+[\"\`\)\'] ]] && return 0
  return 1
}

__cog_skill_lint_check_stage_agnostic_file() {
  local file="$1" failed=0 line line_no=0
  # shellcheck disable=SC2094
  while IFS= read -r line || [[ -n $line ]]; do
    line_no=$((line_no + 1))
    if __cog_skill_lint_line_has_stage_identifier "$line"; then
      __cog_skill_lint_finding "$file" "$line_no" "stage-agnostic-identifiers" \
        "stage-numbered machine identifier present" \
        "name machine-facing files, fields, flags, and ordinal values for their role or content"
      failed=1
    fi
  done <"$file"
  return "$failed"
}

__cog_skill_lint_check_stage_agnostic() {
  local file="$1" failed=0 ref ref_name
  if ! __cog_skill_lint_check_stage_agnostic_file "$file"; then
    failed=1
  fi

  local ref_dir
  ref_dir="$(dirname -- "$file")/references"
  [[ -d $ref_dir ]] || return "$failed"

  while IFS= read -r ref; do
    [[ -n $ref ]] || continue
    ref_name="$(basename -- "$ref")"
    if __cog_skill_lint_line_has_stage_identifier "$ref_name"; then
      __cog_skill_lint_finding "$ref" 1 "stage-agnostic-identifiers" \
        "stage-numbered reference filename present" \
        "rename the reference for its role or content"
      failed=1
    fi
    if [[ -f $ref && -r $ref ]] && ! __cog_skill_lint_check_stage_agnostic_file "$ref"; then
      failed=1
    fi
  done < <(find "$ref_dir" -type f -print 2>/dev/null | sort)

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
# code-review guides to review-oneshot), so the same self-containment golden
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
      __cog_skill_lint_finding "$file" "$line_no" "skill-refs-external-repo-dependency" \
        "runtime skill-refs takes a load-bearing dependency on an external/local docs repository" \
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
    runner-all | runner-plan) printf '%s' "plan-builder-to-queue plan-builder-to-queue-vetted-multi" ;;
    review-findings) printf '%s' "review-code-deep review-oneshot review-loop" ;;
    review-plan-capability-spec) printf '%s' "plan-capability-spec" ;;
    plan-solution-spec) printf '%s' "plan-capability-spec" ;;
    review-plan-solution-spec) printf '%s' "plan-solution-spec plan-capability-spec" ;;
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

# Caller skill name -> space-separated disable-model-invocation target skill names
# it chains inline. Chaining a DMI skill through the harness `Skill` tool fails at
# runtime (the tool refuses a model-initiated call to a DMI skill), so these callers
# must read the target's SKILL.md and execute it inline instead. See ADR-0063.
__cog_skill_lint_inline_skill_tool_dmi_targets() {
  case "$1" in
    plan-vetted) printf '%s' "plan-multi review-plan-multi" ;;
    plan-builder-to-queue) printf '%s' "plan-oneshot review-plan-complexity plan-split" ;;
    plan-builder-to-queue-vetted-multi) printf '%s' "plan-vetted review-plan-multi review-plan-complexity plan-split" ;;
    *) printf '%s' "" ;;
  esac
}

# Returns 0 when the line instructs invoking a skill through the harness `Skill`
# tool rather than reading its SKILL.md and following it inline. Matches the
# phrasings the repo has used: "via the `Skill` tool", the "`Skill` ->" / "`Skill` →"
# dispatch arrow (ASCII or Unicode), and "Use `Skill` to chain". The fixed form's
# negative ("not through the `Skill` tool") contains none of these.
# shellcheck disable=SC2016 # literal backticks in the Skill-tool phrasing, not command substitution
__cog_skill_lint_line_invokes_skill_tool() {
  local line="$1"
  [[ $line == *'via the `Skill` tool'* ]] && return 0
  [[ $line == *'`Skill` →'* ]] && return 0
  [[ $line == *'`Skill` ->'* ]] && return 0
  [[ $line == *'Use `Skill` to chain'* ]] && return 0
  return 1
}

# inline-skill-tool-dmi: a coordinator that chains a disable-model-invocation skill
# must read the target's SKILL.md and execute it inline, never invoke it through the
# harness `Skill` tool (which refuses a model-initiated call to a DMI skill). Scans a
# curated caller set for a Skill-tool-invocation instruction that names one of the
# caller's DMI targets; fenced code blocks are skipped. See ADR-0063 and
# docs/reference/skill-contract.md.
__cog_skill_lint_check_inline_skill_tool_dmi() {
  local file="$1"
  local name targets
  name="$(cog::fn::skill::frontmatter_name "$file")"
  targets="$(__cog_skill_lint_inline_skill_tool_dmi_targets "$name")"
  [[ -z $targets ]] && return 0

  local line line_no=0 failed=0 in_fence=false target
  local fence_re='^[[:space:]]*```+'

  # shellcheck disable=SC2094
  while IFS= read -r line || [[ -n $line ]]; do
    line_no=$((line_no + 1))

    if [[ $line =~ $fence_re ]]; then
      if [[ $in_fence == true ]]; then in_fence=false; else in_fence=true; fi
      continue
    fi
    [[ $in_fence == true ]] && continue

    __cog_skill_lint_line_invokes_skill_tool "$line" || continue
    for target in $targets; do
      if __cog_skill_lint_line_has_producer_token "$line" "$target"; then
        __cog_skill_lint_finding "$file" "$line_no" "inline-skill-tool-dmi" \
          "instructs invoking '${target}' through the Skill tool, but '${target}' sets disable-model-invocation" \
          "invoke '${target}' through a claude-delegate Agent or read \$HOME/.claude/skills/${target}/SKILL.md and follow it inline; do not use the Skill tool"
        failed=1
      fi
    done
  done <"$file"

  return "$failed"
}

# Native-execution executor skills produce the execution report in the
# orchestrator's own session, so the orchestrator holds the Write tool and could
# type a non-canonical filename. cog owns that write (`cog executor adopt`), so
# the skill prose must not instruct a direct write to the canonical execution
# artifact. The prepare artifact is always delegated through a worker's `--output`
# and is not guarded here. See docs/decisions/0046-cog-owned-stage-artifact-writes.md.
__cog_skill_lint_artifact_write_owned_skills() {
  case "$1" in
    executor-oneshot | executor-vetted) return 0 ;;
    *) return 1 ;;
  esac
}

__cog_skill_lint_check_artifact_write_ownership() {
  local file="$1" name
  name="$(cog::fn::skill::frontmatter_name "$file")"
  __cog_skill_lint_artifact_write_owned_skills "$name" || return 0

  local line line_no=0 failed=0 in_fence=false lc
  local fence_re='^[[:space:]]*```+'

  # shellcheck disable=SC2094
  while IFS= read -r line || [[ -n $line ]]; do
    line_no=$((line_no + 1))

    if [[ $line =~ $fence_re ]]; then
      if [[ $in_fence == true ]]; then in_fence=false; else in_fence=true; fi
      continue
    fi
    [[ $in_fence == true ]] && continue

    # The leak is a write imperative whose object is the canonical execution
    # artifact (write ... execution-report.md). A line that only names the
    # artifact (a returns list, a postcondition) or routes through cog/--output is
    # legitimate.
    lc="${line,,}"
    [[ $lc == *execution-report.md* ]] || continue
    [[ $lc =~ (write|save).*execution-report\.md ]] || continue
    [[ $lc == *"cog "* || $lc == *"--output"* ]] && continue

    __cog_skill_lint_finding "$file" "$line_no" "artifact-write-ownership" \
      "instructs a direct write to the canonical execution artifact" \
      "write the report to a working file, then place it with 'cog executor adopt --ordinal execution --from <file>'"
    failed=1
  done <"$file"

  return "$failed"
}

# model-effort-tier: a governed Claude skill's model:/effort: frontmatter must
# resolve to the tier the policy expects for it. The expected tier comes from the
# authoritative registry in data/model-effort/claude (per-tier
# `skills` lists) with a prefix-default fallback; ungoverned skills are exempt.
# Absent model+effort rides the session default (HIGH). The known exceptions
# (executor-prex high; codex launchers, review-findings, review-queue-rounds
# low) live in the registry, not here. See docs/decisions/0047-enforce-prefix-tier-policy.md.
__cog_skill_lint_check_model_effort_tier() {
  local file="$1" runtime name expected model effort actual
  runtime="$(cog::fn::skill::runtime_for_path "$file")"
  [[ $runtime == claude ]] || return 0

  name="$(cog::fn::skill::frontmatter_name "$file")"
  expected="$(cog::fn::skill::expected_tier "$name")"
  [[ $expected == exempt ]] && return 0

  model="$(cog::fn::skill::frontmatter_value "$file" model)"
  effort="$(cog::fn::skill::frontmatter_value "$file" effort)"
  actual="$(cog::fn::skill::tier_for_frontmatter "$model" "$effort")"
  [[ $actual == "$expected" ]] && return 0

  __cog_skill_lint_finding "$file" 1 "model-effort-tier" \
    "model/effort resolves to tier '${actual}' (model=${model:-<default>} effort=${effort:-<default>}) but policy expects tier '${expected}'" \
    "match the expected tier's cell (see 'cog power-grade tier --name ${expected}'), or pin the skill in the right tier's 'skills' list in data/model-effort/claude/tiers.yaml"
  return 1
}

# model-effort-prose-label: a prose reference to a model/effort/power-grade cell
# must name its kind correctly — a cell is a (model, effort) row (named by model@effort
# or its slug); a tier is a named rung (named "the <TIER> tier") — per ADR-0053. Using
# a tier word as the noun "cell" (e.g. "the Codex HIGH cell") conflates the two. Scans
# runtime SKILL.md bodies, skipping frontmatter (governed by model-effort-tier) and
# fenced code blocks (where an explicit `--effort <val>` is already unambiguous). An
# inline `<!-- cog-skill-lint: allow-model-ref-label <reason> -->` on the preceding line
# records a deliberate exception. See docs/decisions/0055-explicit-model-reference-labeling.md.
__cog_skill_lint_check_model_effort_prose_label() {
  local file="$1" runtime
  runtime="$(cog::fn::skill::runtime_for_path "$file")"
  [[ -n $runtime ]] || return 0

  local line line_no=0 failed=0 in_frontmatter=false frontmatter_done=false in_fence=false
  local pending_allow=false lc tier
  local fence_re='^[[:space:]]*```+'
  local marker_re='^[[:space:]]*<!--[[:space:]]*cog-skill-lint:[[:space:]]*allow-model-ref-label[[:space:]]+[^>]*-->[[:space:]]*$'
  local tier_cell_re='(^|[^a-z])(xhigh|high|medium|low|cheap)[[:space:]]+(codex[[:space:]]+|claude[[:space:]]+)?cells?([^a-z]|$)'

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

    if [[ $line =~ $marker_re ]]; then
      pending_allow=true
      continue
    fi

    lc="${line,,}"
    if [[ $lc =~ $tier_cell_re ]]; then
      tier="${BASH_REMATCH[2]}"
      if [[ $pending_allow == true ]]; then
        pending_allow=false
        continue
      fi
      __cog_skill_lint_finding "$file" "$line_no" "model-effort-prose-label" \
        "names a power-grade tier as a cell ('${tier} cell'); a cell is a (model, effort) row, a tier is a named rung" \
        "name the tier ('the ${tier^^} tier') or the explicit cell (model@effort or its slug), per ADR-0053"
      failed=1
    fi

    [[ -n ${line//[[:space:]]/} ]] && pending_allow=false
  done <"$file"

  return "$failed"
}

# skill-class-contract: one positive class-membership assertion that composes the
# scattered facet checks (skill-prefix-taxonomy, model-effort-tier,
# producer-blindness, input-fidelity, stage-agnostic) per the data
# SoT in data/skill-class/contracts.yaml. The facet rules stay authoritative for
# their facet; this rule asserts the per-class union is satisfied for the declared
# class. An ungoverned (other-class) skill passes. See ADR-0016 / DP11.
__cog_skill_lint_check_skill_class() {
  local file="$1" runtime report class failed=0 item
  runtime="$(cog::fn::skill::runtime_for_path "$file")"
  [[ -n $runtime ]] || return 0
  report="$(cog::fn::skill_class::check_json "$file")"
  jq -e '.ok == true' <<<"$report" >/dev/null && return 0
  class="$(jq -r '.class' <<<"$report")"
  while IFS= read -r item; do
    [[ -n $item ]] || continue
    __cog_skill_lint_finding "$file" 1 "skill-class-contract" \
      "class '${class}' contract: missing prerequisite '${item}'" \
      "satisfy the '${class}' class contract (cog skill-class show --class ${class})"
    failed=1
  done < <(jq -r '.missing[]?' <<<"$report")
  while IFS= read -r item; do
    [[ -n $item ]] || continue
    __cog_skill_lint_finding "$file" 1 "skill-class-contract" \
      "class '${class}' contract: forbidden '${item}' present" \
      "remove the prohibited '${item}' (cog skill-class show --class ${class})"
    failed=1
  done < <(jq -r '.forbidden_present[]?' <<<"$report")
  return "$failed"
}

# A bootstrap-* worker whose domain is a valid template-review domain must run the
# shared template-refresh routine so its cog templates stay freshness-tracked. The
# domain is the skill name minus the `bootstrap-` prefix; the allowlist SoT is
# cog::fn::bootstrap_review::valid_domain, so adding a domain there auto-requires this
# reference. bootstrap-rust (domain `rust`, ships no cog templates) and the `bootstrap`
# orchestrator are exempt because their stripped name is not a valid domain.
__cog_skill_lint_check_bootstrap_template_review() {
  local file="$1" runtime name domain
  runtime="$(cog::fn::skill::runtime_for_path "$file")"
  [[ $runtime == claude ]] || return 0
  name="$(cog::fn::skill::frontmatter_name "$file")"
  [[ $name == bootstrap-* ]] || return 0
  domain="${name#bootstrap-}"
  cog::fn::bootstrap_review::valid_domain "$domain" || return 0

  grep -qF "bootstrap-template-review" "$file" && return 0
  __cog_skill_lint_finding "$file" 1 "bootstrap-template-review" \
    "bootstrap worker '${name}' ships cog templates (domain '${domain}') but does not run the template-refresh routine" \
    "follow \$(cog skill-refs path bootstrap/template-refresh-routine.md): cog bootstrap-template-review check|stamp --domain ${domain}"
  return 1
}

# terminal-contract: a curated worker whose run ends with a canonical cog-emitted result line
# must declare that line with a `<!-- cog-terminal-contract: <TOKEN> -->` marker and name the
# token in its prose. The declaration keeps the class visible and blocks reintroducing a
# type-2 "model must remember to emit" ceremony (ADR-0080). The token per worker:
__cog_skill_lint_terminal_contract_token() {
  case "$1" in
    review-loop) printf 'REVIEW_LOOP_OK' ;;
    gc-repo) printf 'COMMIT_OK' ;;
    review-queue-rounds) printf 'STATUS' ;;
    *) return 1 ;;
  esac
}

# The executor-prex -> review-loop boundary is the sole type-2 boundary: its worker's terminal
# step is cog-owned and boundary-finalized. The sibling boundary reference must finalize the
# summary deterministically (`cog review-loop-summary finalize`) and must never fall back to
# re-dispatching an agent (`SendMessage`) to run the terminal step. See ADR-0080.
__cog_skill_lint_check_terminal_contract_boundary() {
  local skill_file="$1" ref failed=0
  ref="$(dirname "$skill_file")/references/review-loop.md"
  [[ -f $ref && -r $ref ]] || return 0

  if ! grep -qF 'cog review-loop-summary finalize' "$ref"; then
    __cog_skill_lint_finding "$ref" 1 "terminal-contract" \
      "review-loop boundary does not finalize the terminal summary deterministically" \
      "run 'cog review-loop-summary finalize --run-dir <child>' from the caller when summary.md is absent"
    failed=1
  fi
  if grep -qF 'SendMessage' "$ref"; then
    __cog_skill_lint_finding "$ref" 1 "terminal-contract" \
      "review-loop boundary re-dispatches an agent to run the terminal step" \
      "run the terminal step deterministically via 'cog review-loop-summary finalize'; do not re-dispatch a worker"
    failed=1
  fi
  return "$failed"
}

__cog_skill_lint_check_terminal_contract() {
  local file="$1" runtime name token failed=0
  runtime="$(cog::fn::skill::runtime_for_path "$file")"
  [[ $runtime == claude ]] || return 0
  name="$(cog::fn::skill::frontmatter_name "$file")"

  if token="$(__cog_skill_lint_terminal_contract_token "$name")"; then
    if ! grep -qF "<!-- cog-terminal-contract: ${token} -->" "$file"; then
      __cog_skill_lint_finding "$file" 1 "terminal-contract" \
        "terminal-contract worker '${name}' missing its declaration marker" \
        "declare the canonical result line: <!-- cog-terminal-contract: ${token} -->"
      failed=1
    fi
    # The token must be documented in prose, not only inside the marker comment.
    if ! grep -F "$token" "$file" | grep -qvF 'cog-terminal-contract:'; then
      __cog_skill_lint_finding "$file" 1 "terminal-contract" \
        "terminal-contract worker '${name}' never documents its result token '${token}'" \
        "describe the '${token}' result line the worker emits"
      failed=1
    fi
  fi

  if [[ $name == executor-prex ]]; then
    __cog_skill_lint_check_terminal_contract_boundary "$file" || failed=1
  fi

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
  if ! __cog_skill_lint_check_input_fidelity "$file"; then
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
  if ! __cog_skill_lint_check_stage_agnostic "$file"; then
    failed=1
  fi
  if ! __cog_skill_lint_check_scratch_in_project "$file"; then
    failed=1
  fi
  if ! __cog_skill_lint_check_codex_abs_artifact "$file"; then
    failed=1
  fi
  if ! __cog_skill_lint_check_codex_output_collision "$file"; then
    failed=1
  fi
  if ! __cog_skill_lint_check_producer_blind "$file"; then
    failed=1
  fi
  if ! __cog_skill_lint_check_inline_skill_tool_dmi "$file"; then
    failed=1
  fi
  if ! __cog_skill_lint_check_artifact_write_ownership "$file"; then
    failed=1
  fi
  if ! __cog_skill_lint_check_model_effort_tier "$file"; then
    failed=1
  fi
  if ! __cog_skill_lint_check_model_effort_prose_label "$file"; then
    failed=1
  fi
  if ! __cog_skill_lint_check_skill_class "$file"; then
    failed=1
  fi
  if ! __cog_skill_lint_check_bootstrap_template_review "$file"; then
    failed=1
  fi
  if ! __cog_skill_lint_check_terminal_contract "$file"; then
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
