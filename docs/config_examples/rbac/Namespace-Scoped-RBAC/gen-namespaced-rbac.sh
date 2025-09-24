#!/usr/bin/env bash
set -euo pipefail

# gen-namespaced-rbac.sh
# Generate (and optionally apply) per-namespace CIS RBAC manifests from the namespaced-role-template.yaml.
#
# Features:
#  - Accept namespaces via: command arguments, -n "ns1 ns2", or -f file (one per line)
#  - Output individual YAML files OR a single combined file
#  - Optionally kubectl apply them directly
#  - Dry-run / echo to stdout mode
#
# Requirements: bash, sed, kubectl (if applying)
#
# Examples:
#   ./gen-namespaced-rbac.sh -n "app1 app2" -o ./out
#   ./gen-namespaced-rbac.sh ns1 ns2 -c combined-namespaces.yaml
#   ./gen-namespaced-rbac.sh -f namespaces.txt -o rbac --apply
#   ./gen-namespaced-rbac.sh -n "ns1" --stdout
#
# namespaces.txt example:
#   team-a
#   team-b
#   team-c
#
# Exit codes:
#  0 success
#  1 usage / validation error
#  2 apply error (kubectl)

TEMPLATE_DEFAULT="$(dirname "$0")/namespaced-role-template.yaml"
TEMPLATE_FILE="$TEMPLATE_DEFAULT"
OUTPUT_DIR=""
COMBINED_FILE=""
APPLY="false"
STDOUT_ONLY="false"
NAMESPACES=()

usage() {
  cat <<EOF
Usage: $0 [options] [namespace ...]
Options:
  -t <template>    Path to namespaced template (default: $TEMPLATE_DEFAULT)
  -n "\"ns1 ns2\""   Space-separated namespace list
  -f <file>        File containing namespace names (one per line, # comments ok)
  -o <dir>         Output directory for per-namespace files (created if missing)
  -c <file>        Write all generated manifests into a single combined file
  --apply          Run 'kubectl apply -f' on each generated file (or combined)
  --stdout         Print concatenated YAML to stdout (overrides -o/-c)
  -h, --help       Show this help

Notes:
  * You may specify namespaces via positional args in place of -n
  * If both -o and -c specified, both are produced (unless --stdout)
  * --apply applies the combined file if -c used, else each individual file
  * --stdout ignores --apply (no direct apply from stdout for safety)
EOF
}

err() { echo "[ERROR] $*" >&2; exit 1; }
info() { echo "[INFO] $*" >&2; }

parse_namespaces_file() {
  local f="$1"
  [[ -f "$f" ]] || err "Namespaces file $f not found"
  while IFS= read -r line; do
    line="${line%%#*}"          # strip comments
    line="${line//[$'\t\r\n ']}" # trim whitespace
    [[ -z "$line" ]] && continue
    NAMESPACES+=("$line")
  done <"$f"
}

while (( $# )); do
  case "$1" in
    -t) shift; TEMPLATE_FILE="${1:-}" ;;
    -n) shift; IFS=' ' read -r -a nsarr <<< "${1:-}"; NAMESPACES+=("${nsarr[@]}") ;;
    -f) shift; parse_namespaces_file "${1:-}" ;;
    -o) shift; OUTPUT_DIR="${1:-}" ;;
    -c) shift; COMBINED_FILE="${1:-}" ;;
    --apply) APPLY="true" ;;
    --stdout) STDOUT_ONLY="true" ;;
    -h|--help) usage; exit 0 ;;
    -*) err "Unknown flag $1" ;;
    *) NAMESPACES+=("$1") ;;
  esac
  shift || true
done

[[ -f "$TEMPLATE_FILE" ]] || err "Template file not found: $TEMPLATE_FILE"
[[ ${#NAMESPACES[@]} -gt 0 ]] || err "No namespaces provided. Use -n, -f, or positional args."

# Deduplicate namespaces
mapfile -t NAMESPACES < <(printf '%s\n' "${NAMESPACES[@]}" | awk 'NF' | sort -u)

if [[ "$STDOUT_ONLY" == "true" ]]; then
  info "Generating manifests to stdout for namespaces: ${NAMESPACES[*]}"
  first=1
  for ns in "${NAMESPACES[@]}"; do
    [[ $first -eq 0 ]] && echo '---'
    sed "s#<NAMESPACE>#$ns#g" "$TEMPLATE_FILE" || err "sed failed for $ns"
    first=0
  done
  exit 0
fi

if [[ -n "$OUTPUT_DIR" ]]; then
  mkdir -p "$OUTPUT_DIR" || err "Failed creating output dir $OUTPUT_DIR"
fi

COMBINED_TMP=""
if [[ -n "$COMBINED_FILE" ]]; then
  : > "$COMBINED_FILE" || err "Cannot write combined file $COMBINED_FILE"
  COMBINED_TMP="$COMBINED_FILE"
fi

APPLY_TARGETS=()

for ns in "${NAMESPACES[@]}"; do
  rendered=$(sed "s#<NAMESPACE>#$ns#g" "$TEMPLATE_FILE") || err "sed failed for $ns"
  if [[ -n "$OUTPUT_DIR" ]]; then
    outFile="$OUTPUT_DIR/rbac-$ns.yaml"
    printf '%s\n' "${rendered}" > "$outFile" || err "Write failed $outFile"
    info "Wrote $outFile"
    APPLY_TARGETS+=("$outFile")
  fi
  if [[ -n "$COMBINED_TMP" ]]; then
    # Add separator if file not empty
    if [[ -s "$COMBINED_TMP" ]]; then echo '---' >> "$COMBINED_TMP"; fi
    printf '%s\n' "${rendered}" >> "$COMBINED_TMP" || err "Append failed $COMBINED_TMP"
  fi
  if [[ -z "$OUTPUT_DIR" && -z "$COMBINED_TMP" ]]; then
    # Neither output nor combined chosen: default to individual file in CWD
    outFile="rbac-$ns.yaml"
    printf '%s\n' "${rendered}" > "$outFile" || err "Write failed $outFile"
    info "Wrote $outFile"
    APPLY_TARGETS+=("$outFile")
  fi

done

if [[ -n "$COMBINED_TMP" ]]; then
  info "Combined manifest written to $COMBINED_TMP"
  APPLY_TARGETS=("$COMBINED_TMP")
fi

if [[ "$APPLY" == "true" ]]; then
  command -v kubectl >/dev/null 2>&1 || err "kubectl not found in PATH"
  for f in "${APPLY_TARGETS[@]}"; do
    info "Applying $f"
    if ! kubectl apply -f "$f"; then
      err "kubectl apply failed for $f"
    fi
  done
  info "Apply complete"
fi

info "Done. Namespaces processed: ${NAMESPACES[*]}"

