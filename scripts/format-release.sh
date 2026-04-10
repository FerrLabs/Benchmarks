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

# Parse all benchmark keys into structured data
declare -A ALL_METHODS ALL_CMDS ALL_FIXTURES ALL_TOOLS
declare -A BENCH_DATA BENCH_MEM

while IFS= read -r key; do
  fixture="" tool="" method="" cmd=""
  for t in semantic-release release-please changesets ferrflow; do
    if [[ "$key" == *"-${t}-"* ]]; then
      tool="$t"
      fixture="${key%%-"$t"-*}"
      rest="${key#*"$t"-}"
      method="${rest%%-*}"
      cmd="${rest#*-}"
      [[ "$cmd" == "$method" ]] && cmd=""
      break
    fi
  done
  [[ -z "$tool" ]] && continue

  ALL_METHODS[$method]=1
  [[ -n "$cmd" ]] && ALL_CMDS[$cmd]=1
  ALL_FIXTURES[$fixture]=1
  ALL_TOOLS[$tool]=1

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

  [[ -n "$cmd" ]] && BENCH_DATA["${fixture}|${tool}|${method}|${cmd}"]="${median}ms${delta}"
  if [[ "$mem" != "N/A" ]]; then
    BENCH_MEM["${fixture}|${tool}|${method}"]="${mem} MB"
  fi
done < <(jq -r '.benchmarks | keys[]' "$LATEST" | sort)

readarray -t CMD_LIST < <(printf '%s\n' "${!ALL_CMDS[@]}" | sort)
readarray -t FIXTURE_LIST < <(printf '%s\n' "${!ALL_FIXTURES[@]}" | sort)

for method in $(printf '%s\n' "${!ALL_METHODS[@]}" | sort); do
  echo "### ${method^}"
  echo ""
  header="| Fixture | Tool |"
  separator="|---------|------|"
  for cmd in "${CMD_LIST[@]}"; do
    header="$header $cmd |"
    separator="$separator------|"
  done
  header="$header Peak RSS |"
  separator="$separator----------|"
  echo "$header"
  echo "$separator"

  for fixture in "${FIXTURE_LIST[@]}"; do
    for tool in $(printf '%s\n' "${!ALL_TOOLS[@]}" | sort); do
      has_data=false
      row="| $fixture | $tool |"
      for cmd in "${CMD_LIST[@]}"; do
        val="${BENCH_DATA["${fixture}|${tool}|${method}|${cmd}"]:-}"
        if [[ -n "$val" ]]; then
          row="$row $val |"
          has_data=true
        else
          row="$row - |"
        fi
      done
      mem="${BENCH_MEM["${fixture}|${tool}|${method}"]:-N/A}"
      row="$row $mem |"
      $has_data && echo "$row"
    done
  done
  echo ""
done

echo "*Binary size: ${BINARY_SIZE} MB — ferrflow ${VERSION}*"
