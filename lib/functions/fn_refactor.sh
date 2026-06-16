# shellcheck shell=bash

__cog_refactor_require_scan_dir() {
  local scan="${1:-}"

  [[ -n $scan ]] || cog::helpers::die "$EX_USAGE" "MissingArgument" \
    "missing scan directory" "function: cog::fn::refactor_scan_fingerprint" \
    "expected <scan_dir>" ""

  [[ -d $scan ]] || cog::helpers::die "$EX_NOINPUT" "InputNotFound" \
    "scan directory not found" "path: ${scan}" "" "check the scan path and retry"
}

cog::fn::refactor_scan_fingerprint() {
  local scan="${1:-}"
  __cog_refactor_require_scan_dir "$scan"

  (
    cd "$scan" \
      && find . -type f -print0 | LC_ALL=C sort -z \
      | xargs -0 cat 2>/dev/null | sha256sum | cut -d' ' -f1
  )
}

cog::fn::refactor_scan_fingerprint_recipe() {
  printf '%s\n' "( cd \"\$SCAN\" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 cat 2>/dev/null | sha256sum | cut -d' ' -f1 )"
}
