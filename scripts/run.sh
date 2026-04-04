#!/usr/bin/env bash
set -euo pipefail

# FerrFlow Benchmark Runner (hyperfine)
#
# Usage: ./run.sh [--json] [--skip-competitors] [--fixtures-dir <path>] [--results-dir <path>]
#
# Requires: ferrflow, hyperfine, jq, /usr/bin/time (GNU), node/npx (for competitors)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FIXTURES_DIR=""
RESULTS_DIR=""
RAW_DIR=""
OUTPUT_FORMAT="markdown"
SKIP_COMPETITORS=false
WARMUP=3
RUNS=10

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) OUTPUT_FORMAT="json"; shift ;;
    --skip-competitors) SKIP_COMPETITORS=true; shift ;;
    --fixtures-dir) FIXTURES_DIR="$2"; shift 2 ;;
    --results-dir) RESULTS_DIR="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# Default paths
if [[ -z "$FIXTURES_DIR" ]]; then
  FIXTURES_DIR="$SCRIPT_DIR/../fixtures"
fi
if [[ -z "$RESULTS_DIR" ]]; then
  RESULTS_DIR="$SCRIPT_DIR/../results"
fi
RAW_DIR="$RESULTS_DIR/raw"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

command_exists() { command -v "$1" &>/dev/null; }

require_cmd() {
  if ! command_exists "$1"; then
    echo "Required command not found: $1" >&2
    exit 1
  fi
}

# Setup minimal config files so competitor tools can run meaningfully
# on the generated fixtures. Without these, most tools exit immediately
# with a config error — benchmarking that is useless.
setup_competitor_config() {
  local tool="$1"
  local dir="$2"

  case "$tool" in
    semantic-release)
      # Use only commit-analyzer and release-notes-generator (no GitHub plugin).
      # Point remote to the local repo via file:// so git fetch succeeds.
      cat > "$dir/.releaserc.json" <<'CONF'
{
  "branches": ["main"],
  "plugins": [
    "@semantic-release/commit-analyzer",
    "@semantic-release/release-notes-generator"
  ]
}
CONF
      git -C "$dir" remote remove origin &>/dev/null || true
      git -C "$dir" remote add origin "file://$dir"
      ;;
    changesets)
      mkdir -p "$dir/.changeset"
      cat > "$dir/.changeset/config.json" <<'CONF'
{
  "$schema": "https://unpkg.com/@changesets/config@3.1.1/schema.json",
  "changelog": false,
  "commit": false,
  "access": "restricted",
  "baseBranch": "main"
}
CONF
      # Create a dummy changeset so `status` has something to evaluate
      local pkg_name="pkg-001"
      if [[ -f "$dir/.ferrflow" ]] && command_exists jq; then
        pkg_name=$(jq -r '.package[0].name // "pkg-001"' "$dir/.ferrflow")
      fi
      cat > "$dir/.changeset/benchmark-dummy.md" <<CONF
---
"$pkg_name": minor
---

benchmark changeset
CONF
      git -C "$dir" add .changeset/benchmark-dummy.md &>/dev/null
      git -C "$dir" commit -m "chore: add benchmark changeset" --allow-empty &>/dev/null || true
      ;;
  esac
}

# Run a command once and check it exits 0. Returns 1 if the tool
# cannot run meaningfully on this fixture.
validate_competitor() {
  local tool="$1"
  local cmd="$2"
  local dir="$3"

  local stderr_file
  stderr_file=$(mktemp)
  if (cd "$dir" && eval "$cmd" >/dev/null 2>"$stderr_file"); then
    rm -f "$stderr_file"
    return 0
  fi
  local reason
  reason=$(tail -1 "$stderr_file" 2>/dev/null || echo "unknown error")
  rm -f "$stderr_file"
  echo "    SKIP $tool: validation failed — $reason" >&2
  return 1
}

# Measure peak RSS in MB (Linux only)
measure_memory() {
  if [[ "$(uname)" == "Linux" ]]; then
    /usr/bin/time -v "$@" 2>&1 >/dev/null | grep "Maximum resident" | awk '{print $6}' | awk '{printf "%.1f", $1/1024}'
  else
    echo "N/A"
  fi
}

# Get binary size in MB
get_binary_size() {
  local path
  path=$(command -v "$1" 2>/dev/null || echo "")
  if [[ -n "$path" && -f "$path" ]]; then
    du -m "$path" | awk '{printf "%.1f", $1}'
  else
    echo "N/A"
  fi
}

# Get npm package install size in MB
get_npm_size() {
  local pkg="$1"
  local tmp_dir
  tmp_dir=$(mktemp -d)
  (
    cd "$tmp_dir"
    npm init -y &>/dev/null
    npm install --save "$pkg" &>/dev/null 2>&1
    du -sm node_modules | awk '{printf "%.1f", $1}'
  )
  rm -rf "$tmp_dir"
}

# Extract median from hyperfine JSON
extract_median() {
  jq '.results[0].median * 1000' "$1" | awk '{printf "%.1f", $1}'
}

# Extract stddev from hyperfine JSON
extract_stddev() {
  jq '.results[0].stddev * 1000' "$1" | awk '{printf "%.1f", $1}'
}

# ---------------------------------------------------------------------------
# Generate fixtures if missing
# ---------------------------------------------------------------------------

if [[ ! -d "$FIXTURES_DIR/single" || ! -d "$FIXTURES_DIR/mono-medium" ]]; then
  echo "Generating fixtures..." >&2
  cargo run --release --bin generate-fixtures -- "$FIXTURES_DIR"
fi

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

require_cmd ferrflow
require_cmd hyperfine
require_cmd jq

mkdir -p "$RAW_DIR"

FIXTURES=("single" "mono-small" "mono-medium" "mono-large")
FIXTURE_LABELS=("single" "mono-small (10 pkg)" "mono-medium (50 pkg)" "mono-large (200 pkg)")
FERRFLOW_CMDS=("check" "release --dry-run" "version" "tag")
FERRFLOW_CMD_NAMES=("check" "release-dry" "version" "tag")
COMPETITOR_FIXTURES=("single" "mono-small" "mono-medium" "mono-large")

FERRFLOW_BIN_SIZE=$(get_binary_size ferrflow)

echo "Running benchmarks..." >&2

# ---------------------------------------------------------------------------
# FerrFlow benchmarks
# ---------------------------------------------------------------------------

for fixture in "${FIXTURES[@]}"; do
  fixture_path="$FIXTURES_DIR/$fixture"
  if [[ ! -d "$fixture_path" ]]; then
    echo "  Fixture not found: $fixture, skipping" >&2
    continue
  fi

  echo "  Fixture: $fixture" >&2

  for i in "${!FERRFLOW_CMDS[@]}"; do
    cmd="${FERRFLOW_CMDS[$i]}"
    cmd_name="${FERRFLOW_CMD_NAMES[$i]}"
    raw_file="$RAW_DIR/${fixture}-ferrflow-${cmd_name}.json"

    echo "    ferrflow $cmd..." >&2
    hyperfine \
      --warmup "$WARMUP" \
      --runs "$RUNS" \
      --export-json "$raw_file" \
      --shell=bash \
      "cd $fixture_path && ferrflow $cmd 2>/dev/null || true" \
      2>/dev/null

    # Memory (single run)
    # shellcheck disable=SC2086
    mem=$(cd "$fixture_path" && measure_memory ferrflow $cmd || true)
    # Stash memory in a sidecar file
    echo "$mem" > "$RAW_DIR/${fixture}-ferrflow-${cmd_name}.mem"
  done
done

# ---------------------------------------------------------------------------
# Competitor benchmarks
# ---------------------------------------------------------------------------

if ! $SKIP_COMPETITORS && command_exists npx; then
  FERRFLOW_NPM_SIZE=$(get_npm_size ferrflow 2>/dev/null || echo "N/A")
  echo "$FERRFLOW_NPM_SIZE" > "$RAW_DIR/ferrflow-npm-size.txt"

  # release-please is excluded: every command requires GitHub API access,
  # there is no local-only mode. Only install size is measured (below).
  declare -A COMPETITOR_CMDS=(
    ["semantic-release"]="npx --yes semantic-release --dry-run --no-ci"
    ["changesets"]="npx --yes @changesets/cli status"
  )
  declare -A COMPETITOR_PKGS=(
    ["semantic-release"]="semantic-release"
    ["changesets"]="@changesets/cli"
    ["release-please"]="release-please"
  )

  for tool in "semantic-release" "changesets"; do
    tool_cmd="${COMPETITOR_CMDS[$tool]}"
    pkg="${COMPETITOR_PKGS[$tool]}"

    # Install size (once)
    echo "  Measuring $tool install size..." >&2
    npm_size=$(get_npm_size "$pkg" 2>/dev/null || echo "N/A")
    echo "$npm_size" > "$RAW_DIR/${tool}-npm-size.txt"

    for fixture in "${COMPETITOR_FIXTURES[@]}"; do
      fixture_path="$FIXTURES_DIR/$fixture"
      if [[ ! -d "$fixture_path" ]]; then continue; fi

      raw_file="$RAW_DIR/${fixture}-${tool}-check.json"

      echo "    $tool on $fixture..." >&2
      # Run in a temp copy to avoid polluting fixtures
      tmp_dir=$(mktemp -d)
      cp -a "$fixture_path/." "$tmp_dir/"

      setup_competitor_config "$tool" "$tmp_dir"

      if ! validate_competitor "$tool" "$tool_cmd" "$tmp_dir"; then
        echo "N/A" > "$RAW_DIR/${fixture}-${tool}-check.mem"
        rm -rf "$tmp_dir"
        continue
      fi

      hyperfine \
        --warmup 1 \
        --runs 3 \
        --export-json "$raw_file" \
        --shell=bash \
        "cd $tmp_dir && $tool_cmd 2>/dev/null" \
        2>/dev/null

      if [[ ! -s "$raw_file" ]]; then
        echo "    WARN: $tool on $fixture produced no benchmark results" >&2
        rm -rf "$tmp_dir"
        continue
      fi

      # shellcheck disable=SC2086
      mem=$(cd "$tmp_dir" && measure_memory $tool_cmd 2>/dev/null || echo "N/A")
      echo "$mem" > "$RAW_DIR/${fixture}-${tool}-check.mem"

      rm -rf "$tmp_dir"
    done
  done
  # Measure release-please install size (no runtime benchmark — requires GitHub API)
  echo "  Measuring release-please install size..." >&2
  rp_size=$(get_npm_size "release-please" 2>/dev/null || echo "N/A")
  echo "$rp_size" > "$RAW_DIR/release-please-npm-size.txt"
else
  echo "  Skipping competitors (npx not available or --skip-competitors)" >&2
fi

# ---------------------------------------------------------------------------
# Aggregate results into latest.json
# ---------------------------------------------------------------------------

TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
FERRFLOW_VERSION=$(ferrflow --version 2>/dev/null | head -1 || echo "unknown")
FERRFLOW_NPM_SIZE=$(cat "$RAW_DIR/ferrflow-npm-size.txt" 2>/dev/null || echo "N/A")

{
  echo "{"
  echo "  \"timestamp\": \"$TIMESTAMP\","
  echo "  \"ferrflow_version\": \"$FERRFLOW_VERSION\","
  echo "  \"ferrflow_binary_size_mb\": \"$FERRFLOW_BIN_SIZE\","
  echo "  \"ferrflow_npm_size_mb\": \"$FERRFLOW_NPM_SIZE\","
  echo "  \"benchmarks\": {"

  first_bench=true
  for fixture in "${FIXTURES[@]}"; do
    for i in "${!FERRFLOW_CMD_NAMES[@]}"; do
      cmd_name="${FERRFLOW_CMD_NAMES[$i]}"
      raw_file="$RAW_DIR/${fixture}-ferrflow-${cmd_name}.json"
      mem_file="$RAW_DIR/${fixture}-ferrflow-${cmd_name}.mem"
      if [[ ! -f "$raw_file" ]]; then continue; fi

      median=$(extract_median "$raw_file")
      stddev=$(extract_stddev "$raw_file")
      mem=$(cat "$mem_file" 2>/dev/null || echo "N/A")

      if ! $first_bench; then echo ","; fi
      first_bench=false
      printf '    "ferrflow|%s|%s": {"median_ms": %s, "stddev_ms": %s, "memory_mb": "%s"}' \
        "$fixture" "$cmd_name" "$median" "$stddev" "$mem"
    done
  done

  # Competitors (only tools with runtime benchmarks)
  for tool in "semantic-release" "changesets"; do
    for fixture in "${COMPETITOR_FIXTURES[@]}"; do
      raw_file="$RAW_DIR/${fixture}-${tool}-check.json"
      mem_file="$RAW_DIR/${fixture}-${tool}-check.mem"
      if [[ ! -f "$raw_file" ]]; then continue; fi

      median=$(extract_median "$raw_file" 2>/dev/null || echo "0")
      stddev=$(extract_stddev "$raw_file" 2>/dev/null || echo "0")
      mem=$(cat "$mem_file" 2>/dev/null || echo "N/A")
      npm_size=$(cat "$RAW_DIR/${tool}-npm-size.txt" 2>/dev/null || echo "N/A")

      if ! $first_bench; then echo ","; fi
      first_bench=false
      printf '    "%s|%s|check": {"median_ms": %s, "stddev_ms": %s, "memory_mb": "%s", "npm_size_mb": "%s"}' \
        "$tool" "$fixture" "$median" "$stddev" "$mem" "$npm_size"
    done
  done

  echo ""
  echo "  }"
  echo "}"
} > "$RESULTS_DIR/latest.json"

echo "" >&2
echo "Results saved to $RESULTS_DIR/latest.json" >&2

# ---------------------------------------------------------------------------
# Markdown output
# ---------------------------------------------------------------------------

if [[ "$OUTPUT_FORMAT" == "json" ]]; then
  cat "$RESULTS_DIR/latest.json"
else
  for i in "${!FIXTURES[@]}"; do
    fixture="${FIXTURES[$i]}"
    label="${FIXTURE_LABELS[$i]}"

    echo ""
    echo "### ${label}"
    echo ""
    echo "| Tool | Command | Median | Stddev | Binary/Install | Memory (RSS) |"
    echo "|------|---------|--------|--------|----------------|--------------|"

    # FerrFlow rows
    for j in "${!FERRFLOW_CMD_NAMES[@]}"; do
      cmd_name="${FERRFLOW_CMD_NAMES[$j]}"
      cmd="${FERRFLOW_CMDS[$j]}"
      raw_file="$RAW_DIR/${fixture}-ferrflow-${cmd_name}.json"
      mem_file="$RAW_DIR/${fixture}-ferrflow-${cmd_name}.mem"
      if [[ ! -f "$raw_file" ]]; then continue; fi

      median=$(extract_median "$raw_file")
      stddev=$(extract_stddev "$raw_file")
      mem=$(cat "$mem_file" 2>/dev/null || echo "N/A")

      size_col="$FERRFLOW_BIN_SIZE MB"
      if [[ "$FERRFLOW_NPM_SIZE" != "N/A" ]]; then
        size_col="$FERRFLOW_BIN_SIZE MB / $FERRFLOW_NPM_SIZE MB (npm)"
      fi

      echo "| ferrflow | $cmd | ${median}ms | ${stddev}ms | $size_col | ${mem} MB |"
    done

    # Competitor rows
    for tool in "semantic-release" "changesets"; do
      raw_file="$RAW_DIR/${fixture}-${tool}-check.json"
      mem_file="$RAW_DIR/${fixture}-${tool}-check.mem"
      if [[ ! -f "$raw_file" ]]; then continue; fi

      median=$(extract_median "$raw_file" 2>/dev/null || echo "N/A")
      stddev=$(extract_stddev "$raw_file" 2>/dev/null || echo "N/A")
      mem=$(cat "$mem_file" 2>/dev/null || echo "N/A")
      npm_size=$(cat "$RAW_DIR/${tool}-npm-size.txt" 2>/dev/null || echo "N/A")

      echo "| $tool | check | ${median}ms | ${stddev}ms | ${npm_size} MB | ${mem} MB |"
    done
  done
fi
