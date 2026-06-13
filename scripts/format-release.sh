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

echo "## Performance"
echo ""

# Parse all benchmark keys into structured data
declare -A ALL_METHODS ALL_CMDS ALL_FIXTURES ALL_TOOLS
declare -A BENCH_DATA BENCH_MEM

while IFS= read -r key; do
  fixture="" tool="" method="" cmd=""
  for t in commit-and-tag-version standard-version semantic-release release-please changesets ferrflow; do
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

  # Track tools that produced data in this method's section so we can
  # add a transparency note when only ferrflow has rows (typical for
  # `binary` and `docker`, since every competitor is a Node package
  # with no native binary or first-party Docker image to compare
  # against). Otherwise the empty sections look like a competitor's
  # data was lost or filtered out, when in reality there's nothing to
  # measure.
  declare -A METHOD_TOOLS_WITH_DATA=()
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
      if $has_data; then
        echo "$row"
        METHOD_TOOLS_WITH_DATA[$tool]=1
      fi
    done
  done

  case "$method" in
    binary)
      if [[ ${#METHOD_TOOLS_WITH_DATA[@]} -le 1 ]]; then
        echo ""
        echo "_Note: every competitor is a Node.js package — none ship a native binary, so this section can only show \`ferrflow\`. Cross-tool comparisons live in the **Npm** section._"
      fi
      ;;
    docker)
      if [[ ${#METHOD_TOOLS_WITH_DATA[@]} -le 1 ]]; then
        echo ""
        echo "_Note: no competitor publishes a first-party Docker image that is comparable to \`ghcr.io/ferrlabs/ferrflow\` (a single static binary). Wrapping the Node tools in \`node:lts\` would only re-time \`node startup + npm + the tool\` already measured in the **Npm** section, so this section is intentionally limited to \`ferrflow\`._"
      fi
      ;;
  esac

  unset METHOD_TOOLS_WITH_DATA
  echo ""
done

has_install_sizes=$(jq -r 'if has("install_sizes") and (.install_sizes | length > 0) then "yes" else "no" end' "$LATEST")
if [[ "$has_install_sizes" == "yes" ]]; then
  echo ""
  echo "### Install footprint"
  echo ""
  echo "| Tool | npm | binary |"
  echo "|------|-----|--------|"
  while IFS= read -r tool; do
    npm_size=$(jq -r --arg t "$tool" '.install_sizes[$t].npm // "—"' "$LATEST")
    bin_size=$(jq -r --arg t "$tool" '.install_sizes[$t].binary // "—"' "$LATEST")
    [[ "$npm_size" != "—" ]] && npm_size="${npm_size} MB"
    [[ "$bin_size" != "—" ]] && bin_size="${bin_size} MB"
    echo "| ${tool} | ${npm_size} | ${bin_size} |"
  done < <(jq -r '.install_sizes | keys[]' "$LATEST" | sort)
  echo ""
fi
