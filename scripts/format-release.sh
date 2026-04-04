#!/usr/bin/env bash
set -euo pipefail

# Format benchmark results from latest.json as a compact markdown table
# suitable for GitHub Release bodies and Step Summaries.
#
# Usage: ./format-release.sh <latest.json> [--with-delta <baseline.json>]
#
# Requires: jq

LATEST="${1:-}"
BASELINE=""

shift || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-delta) BASELINE="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [[ -z "$LATEST" || ! -f "$LATEST" ]]; then
  echo "Usage: $0 <latest.json> [--with-delta <baseline.json>]" >&2
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "Required command not found: jq" >&2
  exit 1
fi

VERSION=$(jq -r '.ferrflow_version' "$LATEST")
BINARY_SIZE=$(jq -r '.ferrflow_binary_size_mb' "$LATEST")

echo "## Performance"
echo ""
echo "| Fixture | Tool | Method | Command | Median | Memory |"
echo "|---------|------|--------|---------|--------|--------|"

jq -r '.benchmarks | keys[]' "$LATEST" | sort | while IFS= read -r key; do
  # Parse key: fixture-tool-method-cmd
  # Split on '-' but tool names can contain '-' (semantic-release)
  # Use jq to get median/stddev
  median=$(jq -r ".benchmarks[\"$key\"].median_ms" "$LATEST" | awk '{printf "%.1f", $1}')
  mem=$(jq -r ".benchmarks[\"$key\"].memory_mb" "$LATEST")

  delta=""
  if [[ -n "$BASELINE" && -f "$BASELINE" ]]; then
    old=$(jq -r ".benchmarks[\"$key\"].median_ms // empty" "$BASELINE" 2>/dev/null || echo "")
    if [[ -n "$old" && "$old" != "null" ]]; then
      pct=$(awk "BEGIN {printf \"%.0f\", (($median - $old) / $old) * 100}")
      if [[ "$pct" -gt 0 ]]; then
        delta=" (+${pct}%)"
      elif [[ "$pct" -lt 0 ]]; then
        delta=" (${pct}%)"
      fi
    fi
  fi

  mem_display="N/A"
  if [[ "$mem" != "N/A" ]]; then
    mem_display="${mem} MB"
  fi

  echo "| ${key} | ${median}ms${delta} | ${mem_display} |"
done

echo ""
echo "*Binary size: ${BINARY_SIZE} MB — ferrflow ${VERSION}*"
