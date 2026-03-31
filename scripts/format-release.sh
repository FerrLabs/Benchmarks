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
echo "| Fixture | Command | Median | Memory |"
echo "|---------|---------|--------|--------|"

jq -r '
  .benchmarks | to_entries[]
  | select(.key | startswith("ferrflow|"))
  | .key
' "$LATEST" | sort | while IFS= read -r key; do
  fixture=$(echo "$key" | cut -d'|' -f2)
  cmd=$(echo "$key" | cut -d'|' -f3)

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

  echo "| ${fixture} | ${cmd} | ${median}ms${delta} | ${mem_display} |"
done

# ---------------------------------------------------------------------------
# Competitor comparison (only when competitor data is present)
# ---------------------------------------------------------------------------

COMPETITOR_KEYS=$(jq -r '
  .benchmarks | keys[] | select(startswith("ferrflow|") | not)
' "$LATEST" 2>/dev/null || true)

if [[ -n "$COMPETITOR_KEYS" ]]; then
  # Collect fixtures that have both ferrflow and competitor data
  COMP_FIXTURES=$(echo "$COMPETITOR_KEYS" | cut -d'|' -f2 | sort -u)

  echo ""
  echo "### vs. competitors"
  echo ""
  echo "| Fixture | Tool | Median | Memory |"
  echo "|---------|------|--------|--------|"

  echo "$COMP_FIXTURES" | while IFS= read -r fixture; do
    # FerrFlow check for this fixture
    ff_key="ferrflow|${fixture}|check"
    ff_median=$(jq -r ".benchmarks[\"$ff_key\"].median_ms // empty" "$LATEST" 2>/dev/null || echo "")
    ff_mem=$(jq -r ".benchmarks[\"$ff_key\"].memory_mb // empty" "$LATEST" 2>/dev/null || echo "")

    if [[ -n "$ff_median" && "$ff_median" != "null" ]]; then
      ff_median_fmt=$(echo "$ff_median" | awk '{printf "%.1f", $1}')
      ff_mem_display="N/A"
      if [[ -n "$ff_mem" && "$ff_mem" != "N/A" && "$ff_mem" != "null" ]]; then
        ff_mem_display="${ff_mem} MB"
      fi
      echo "| ${fixture} | **ferrflow** | **${ff_median_fmt}ms** | **${ff_mem_display}** |"
    fi

    # Competitor entries for this fixture
    echo "$COMPETITOR_KEYS" | grep "|${fixture}|" | sort | while IFS= read -r ckey; do
      tool=$(echo "$ckey" | cut -d'|' -f1)
      c_median=$(jq -r ".benchmarks[\"$ckey\"].median_ms // empty" "$LATEST" 2>/dev/null || echo "")
      c_mem=$(jq -r ".benchmarks[\"$ckey\"].memory_mb // empty" "$LATEST" 2>/dev/null || echo "")

      if [[ -z "$c_median" || "$c_median" == "null" || "$c_median" == "0" ]]; then
        continue
      fi

      c_median_fmt=$(echo "$c_median" | awk '{printf "%.1f", $1}')
      c_mem_display="N/A"
      if [[ -n "$c_mem" && "$c_mem" != "N/A" && "$c_mem" != "null" ]]; then
        c_mem_display="${c_mem} MB"
      fi

      # Compute slowdown factor vs ferrflow
      slowdown=""
      if [[ -n "$ff_median" && "$ff_median" != "null" ]]; then
        slowdown=$(awk "BEGIN {x = $c_median / $ff_median; if (x >= 1.5) printf \" (%.0fx)\", x}")
      fi

      echo "| ${fixture} | ${tool} | ${c_median_fmt}ms${slowdown} | ${c_mem_display} |"
    done
  done
fi

echo ""
echo "*Binary size: ${BINARY_SIZE} MB — ferrflow ${VERSION}*"
