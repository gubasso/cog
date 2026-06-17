# shellcheck shell=bash
: 'desc: Run deterministic source static-analysis probes.'

__cog_refactor_scan_source_self_check='(.ok|type=="boolean") and (.source_root|type=="string") and (.run_dir|type=="string") and (.scan_dir|type=="string") and (.outputs|type=="object") and (.counts.manifest_hits|type=="number") and (.counts.test_hits|type=="number") and (.fingerprint|type=="string") and (.notes|type=="array")'

__cog_refactor_scan_source_usage() {
  cog::fn::ui_data "Usage: cog refactor-scan-source --source-root <dir> --run-dir <dir> (<out.json>|--json)"
}

__cog_refactor_scan_source_count_lines() {
  [[ -f $1 ]] || { printf '0\n'; return 0; }
  wc -l <"$1" | tr -d ' '
}

__cog_refactor_scan_source_run_scan() {
  local source_root="$1" run_dir="$2" scan="$3" f
  rm -rf "$scan"
  mkdir -p "$scan"
  ls -la "$source_root" >"$scan/root-ls.txt" 2>&1
  find "$source_root" -maxdepth 6 -type f \
    \( -name 'Cargo.toml' -o -name 'go.mod' -o -name 'package.json' -o -name 'pyproject.toml' -o -name 'setup.py' \
    -o -name 'Gemfile' -o -name 'pom.xml' -o -name 'build.gradle' -o -name 'build.gradle.kts' -o -name '*.cabal' \
    -o -name 'mix.exs' -o -name 'composer.json' -o -name 'CMakeLists.txt' \) \
    -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null >"$scan/manifests.txt"
  : >"$scan/readme-excerpt.txt"
  for f in README.md README.rst README docs/README.md; do
    if [[ -f $source_root/$f ]]; then head -200 "$source_root/$f" >"$scan/readme-excerpt.txt"; break; fi
  done
  (cd "$source_root" &&
    find . -type f \( -name '*.rs' -o -name '*.go' -o -name '*.py' -o -name '*.ts' -o -name '*.js' -o -name '*.rb' \
      -o -name '*.sh' -o -name '*.bash' -o -name '*.java' -o -name '*.kt' -o -name '*.c' -o -name '*.cc' \
      -o -name '*.cpp' -o -name '*.h' -o -name '*.hpp' \) \
      -not -path './.git/*' -not -path './node_modules/*' -not -path './target/*' -not -path './dist/*' \
      -not -path './build/*' -not -path './venv/*' -not -path './.venv/*' -not -path './vendor/*' \
      -not -path './.cargo/*' -not -path './third_party/*' -not -path './third-party/*' -print0 |
    xargs -0 wc -l 2>/dev/null | tail -1) >"$scan/loc.txt" 2>&1
  [[ -s $scan/loc.txt ]] || echo "0 total" >"$scan/loc.txt"
  find "$source_root" -type f \( -name '*_test.*' -o -name 'test_*' -o -name '*.test.*' -o -path '*/tests/*' -o -path '*/test/*' -o -path '*/spec/*' \) \
    -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/target/*' | head -200 >"$scan/tests.txt"
  grep -rh --include='*.rs' -E '^pub (fn|struct|enum|trait|mod)' "$source_root" 2>/dev/null | head -200 >"$scan/public-rust.txt" || true
  grep -rh --include='*.go' -E '^(func|type|var|const) [A-Z]' "$source_root" 2>/dev/null | head -200 >"$scan/public-go.txt" || true
  grep -rh --include='*.py' -E '^(def [a-zA-Z]|class [A-Z])' "$source_root" 2>/dev/null | head -200 >"$scan/public-python.txt" || true
  grep -rEh '(exit|sys\.exit|os\.Exit|process\.exit)\s*\(\s*[0-9]+' "$source_root" 2>/dev/null | head -100 >"$scan/exit-codes.txt" || true
  grep -rlEh '(clap|argparse|cobra|typer|click|yargs|commander|getopts)' "$source_root" 2>/dev/null | head -50 >"$scan/cli-parser-hints.txt" || true
  find "$source_root" -type f \( -name 'openapi*.y*ml' -o -name 'openapi*.json' -o -name 'swagger*.y*ml' -o -name 'swagger*.json' -o -name '*.proto' -o -name 'schema.graphql' -o -name '*.sdl' \) 2>/dev/null >"$scan/api-schemas.txt"
  find "$source_root" -maxdepth 6 -type f \( -name 'config.y*ml' -o -name 'config.toml' -o -name 'config.json' -o -name '*.config.*' -o -name 'settings.*' -o -name 'app.*' \) \
    -not -path '*/.git/*' -not -path '*/node_modules/*' 2>/dev/null | head -50 >"$scan/configs.txt"
  printf '%s\n' 'not captured: git execution disabled for this helper round' >"$scan/source-git-head.txt"
  for f in Cargo.toml go.mod package.json pyproject.toml setup.py Gemfile pom.xml; do [[ -f $source_root/$f ]] && cp "$source_root/$f" "$scan/manifest-$f" 2>/dev/null || true; done
  cog::fn::refactor_scan_fingerprint "$scan" >"$run_dir/scan-fingerprint.txt"
}

__cog_refactor_scan_source_build_json() {
  local source_root="$1" run_dir="$2" scan fingerprint manifest_hits test_hits config_hits notes
  source_root="$(realpath "$source_root")"
  run_dir="$(realpath -m "$run_dir")"
  scan="$run_dir/source-scan"
  [[ -d $source_root ]] || cog::fn::error_raise "InputNotFound" "source root not found" "path: ${source_root}" "" "check source root"
  mkdir -p "$run_dir"
  __cog_refactor_scan_source_run_scan "$source_root" "$run_dir" "$scan"
  fingerprint="$(<"$run_dir/scan-fingerprint.txt")"
  manifest_hits="$(__cog_refactor_scan_source_count_lines "$scan/manifests.txt")"
  test_hits="$(__cog_refactor_scan_source_count_lines "$scan/tests.txt")"
  config_hits="$(__cog_refactor_scan_source_count_lines "$scan/configs.txt")"
  notes="$(jq -cn '["source-git-head.txt placeholder written because git execution is disabled for this helper round"]')"
  jq -n --argjson ok true --arg source_root "$source_root" --arg run_dir "$run_dir" --arg scan_dir "$scan" \
    --argjson outputs '{"root_ls":"root-ls.txt","manifests":"manifests.txt","readme_excerpt":"readme-excerpt.txt","loc":"loc.txt","tests":"tests.txt","fingerprint":"../scan-fingerprint.txt"}' \
    --argjson manifest_hits "$manifest_hits" --argjson test_hits "$test_hits" --argjson config_hits "$config_hits" \
    --arg fingerprint "$fingerprint" --argjson notes "$notes" \
    '{ok: $ok, source_root: $source_root, run_dir: $run_dir, scan_dir: $scan_dir, outputs: $outputs,
      counts: {manifest_hits: $manifest_hits, test_hits: $test_hits, config_hits: $config_hits},
      fingerprint: $fingerprint, notes: $notes}'
}

cog::cmd::refactor_scan_source() {
  local source_root="" run_dir="" mode="" out="" json
  while (($# > 0)); do
    case "$1" in
      -h | --help) __cog_refactor_scan_source_usage; return 0 ;;
      --source-root) [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing source root" "option: --source-root" "" "run 'cog refactor-scan-source --help'"; source_root="$2"; shift 2 ;;
      --run-dir) [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing run dir" "option: --run-dir" "" "run 'cog refactor-scan-source --help'"; run_dir="$2"; shift 2 ;;
      --json) [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" "duplicate refactor-scan-source output mode" "" "" "choose either --json or an output path"; mode=json; shift ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown refactor-scan-source option" "option: $1" "" "run 'cog refactor-scan-source --help'" ;;
      *) [[ -z $mode && -z $out ]] || cog::fn::error_raise "TooManyArguments" "too many refactor-scan-source output paths" "argument: $1" "" "run 'cog refactor-scan-source --help'"; out="$1"; mode=file; shift ;;
    esac
  done
  [[ -n $source_root && -n $run_dir && (-n $mode || ${COG_UI_JSON:-false} == true) ]] || cog::fn::error_raise "MissingArgument" "missing refactor-scan-source argument" "usage: cog refactor-scan-source --source-root <dir> --run-dir <dir> (<out.json>|--json)" "" "run 'cog refactor-scan-source --help'"
  [[ -n $mode ]] || mode=json
  json="$(__cog_refactor_scan_source_build_json "$source_root" "$run_dir")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then cog::fn::json_emit "$__cog_refactor_scan_source_self_check" "$json"; else cog::fn::json_write_fragment "$out" "$__cog_refactor_scan_source_self_check" "$json"; fi
}
