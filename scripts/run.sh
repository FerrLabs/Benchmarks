#!/usr/bin/env bash
set -euo pipefail

# FerrFlow Benchmark Runner (hyperfine)
#
# Usage: ./run.sh [--json] [--skip-competitors] [--fixtures-dir <path>]
#                 [--results-dir <path>] [--definitions-dir <path>]
#
# Requires: ferrflow, hyperfine, jq

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOLS_JSON="$SCRIPT_DIR/../tools.json"
FIXTURES_DIR=""
RESULTS_DIR=""
DEFINITIONS_DIR=""
RAW_DIR=""
OUTPUT_FORMAT="markdown"
SKIP_COMPETITORS=false
VERBOSE="${VERBOSE:-false}"
WARMUP=3
RUNS=10

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) OUTPUT_FORMAT="json"; shift ;;
    --skip-competitors) SKIP_COMPETITORS=true; shift ;;
    --verbose) VERBOSE=true; shift ;;
    --fixtures-dir) FIXTURES_DIR="$2"; shift 2 ;;
    --results-dir) RESULTS_DIR="$2"; shift 2 ;;
    --definitions-dir) DEFINITIONS_DIR="$2"; shift 2 ;;
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

# Write tool_configs files from a definition into a directory
write_tool_configs() {
  local tool="$1"
  local target_dir="$2"
  local def_file="$3"

  if [[ -z "$def_file" || ! -f "$def_file" ]]; then
    return
  fi

  # Extract tool_configs.<tool> and write each file
  local files
  files=$(jq -r --arg t "$tool" '.tool_configs[$t] // {} | to_entries[] | "\(.key)\t\(.value)"' "$def_file" 2>/dev/null) || return 0

  while IFS=$'\t' read -r path content; do
    [[ -z "$path" ]] && continue
    local full_path="$target_dir/$path"
    mkdir -p "$(dirname "$full_path")"
    echo "$content" > "$full_path"
  done <<< "$files"
}

# Auto-generate ferrflow config for bulk fixtures with empty config
prepare_ferrflow_fixture() {
  local dir="$1"
  local config_file="$dir/ferrflow.json"

  [[ -f "$config_file" ]] || return 0
  local content
  content=$(cat "$config_file")
  [[ "$content" == "{}" ]] || return 0

  local pkgs=()
  for pkg_json in "$dir"/packages/*/package.json; do
    [[ -f "$pkg_json" ]] || continue
    local pkg_name pkg_path
    pkg_name=$(jq -r '.name' "$pkg_json")
    pkg_path=$(dirname "$pkg_json")
    pkg_path="${pkg_path#"$dir/"}"
    pkgs+=("{\"name\":\"$pkg_name\",\"path\":\"$pkg_path\",\"versioned_files\":[{\"path\":\"$pkg_path/package.json\",\"format\":\"json\"}]}")
  done

  if [[ ${#pkgs[@]} -gt 0 ]]; then
    local joined
    joined=$(IFS=,; echo "${pkgs[*]}")
    echo "{\"package\":[$joined]}" > "$config_file"
  fi
}

# Set up a dummy bare remote for tools that require one (semantic-release, etc.)
setup_dummy_remote() {
  local dir="$1"
  local bare_dir="$2"

  [[ -d "$dir/.git" ]] || return 0
  git -C "$bare_dir" init --bare -q 2>/dev/null
  git -C "$dir" remote add origin "$bare_dir" 2>/dev/null || true
  git -C "$dir" push -q origin HEAD 2>/dev/null || true
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
# Setup
# ---------------------------------------------------------------------------

require_cmd hyperfine
require_cmd jq

mkdir -p "$RAW_DIR"

# Read tool definitions
TOOLS=$(jq -r 'keys[]' "$TOOLS_JSON")

# Discover fixtures from generated dir
FIXTURES=()
for d in "$FIXTURES_DIR"/*/; do
  [[ -d "$d" ]] && FIXTURES+=("$(basename "$d")")
done

if [[ ${#FIXTURES[@]} -eq 0 ]]; then
  echo "No fixtures found in $FIXTURES_DIR" >&2
  exit 1
fi

echo "Running benchmarks..." >&2
echo "  Fixtures: ${FIXTURES[*]}" >&2
echo "  Tools: $TOOLS" >&2

# ---------------------------------------------------------------------------
# Run benchmarks per tool
# ---------------------------------------------------------------------------

for tool in $TOOLS; do
  # Skip competitors if requested
  if $SKIP_COMPETITORS && [[ "$tool" != "ferrflow" ]]; then
    echo "  Skipping $tool (--skip-competitors)" >&2
    continue
  fi

  # Read tool config from tools.json
  install_methods=$(jq -r --arg t "$tool" '.[$t].install_methods | keys[]' "$TOOLS_JSON")
  # commands are read per-fixture below via jq

  for method in $install_methods; do
    tool_cmd=$(jq -r --arg t "$tool" --arg m "$method" '.[$t].install_methods[$m].command' "$TOOLS_JSON")
    setup_cmd=$(jq -r --arg t "$tool" --arg m "$method" '.[$t].install_methods[$m].setup // empty' "$TOOLS_JSON")

    # Check if the tool is available
    local_bin=$(echo "$tool_cmd" | awk '{print $1}')
    if [[ "$method" == "binary" ]] && ! command_exists "$local_bin"; then
      echo "  SKIP $tool/$method: $local_bin not found" >&2
      continue
    fi
    if [[ "$method" == "npm" ]] && ! command_exists npx; then
      echo "  SKIP $tool/$method: npx not available" >&2
      continue
    fi
    if [[ "$method" == "docker" ]] && ! command_exists docker; then
      echo "  SKIP $tool/$method: docker not available" >&2
      continue
    fi

    # Run setup if needed
    if [[ -n "$setup_cmd" ]]; then
      echo "  Setting up $tool/$method..." >&2
      eval "$setup_cmd" &>/dev/null 2>&1 || {
        echo "  SKIP $tool/$method: setup failed" >&2
        continue
      }
    fi

    # Measure install size
    if [[ "$method" == "npm" ]]; then
      pkg_name=$(echo "$setup_cmd" | grep -oP 'install -g \K\S+' || echo "$tool")
      echo "  Measuring $tool npm install size..." >&2
      npm_size=$(get_npm_size "$pkg_name" 2>/dev/null || echo "N/A")
      echo "$npm_size" > "$RAW_DIR/${tool}-npm-size.txt"
    fi
    if [[ "$method" == "binary" && "$tool" == "ferrflow" ]]; then
      bin_size=$(get_binary_size ferrflow)
      echo "$bin_size" > "$RAW_DIR/ferrflow-binary-size.txt"
    fi

    for fixture in "${FIXTURES[@]}"; do
      fixture_path="$FIXTURES_DIR/$fixture"
      if [[ ! -d "$fixture_path" ]]; then
        continue
      fi

      # Find the definition file for this fixture
      def_file=""
      if [[ -n "$DEFINITIONS_DIR" && -f "$DEFINITIONS_DIR/${fixture}.json" ]]; then
        def_file="$DEFINITIONS_DIR/${fixture}.json"
      fi

      # Work on a copy so tool configs don't pollute the original
      tmp_dir=$(mktemp -d)
      bare_remote=""
      cp -a "$fixture_path/." "$tmp_dir/"

      # Write tool-specific config files
      write_tool_configs "$tool" "$tmp_dir" "$def_file"

      # Tool-specific fixture preparation
      if [[ "$tool" == "ferrflow" ]]; then
        prepare_ferrflow_fixture "$tmp_dir"
      else
        bare_remote=$(mktemp -d)
        setup_dummy_remote "$tmp_dir" "$bare_remote"
      fi

      # Build commands to benchmark
      readarray -t cmds < <(jq -r --arg t "$tool" '.[$t].commands[]' "$TOOLS_JSON")

      for cmd in "${cmds[@]}"; do
        # For tools with empty command (semantic-release, changesets), the full command is in tool_cmd
        if [[ -z "$cmd" ]]; then
          full_cmd="$tool_cmd"
          cmd_name="check"
        else
          full_cmd="$tool_cmd $cmd"
          cmd_name=$(echo "$cmd" | tr ' ' '-' | tr -d '-')
          # Normalize: "release --dry-run" -> "release-dry"
          cmd_name=$(echo "$cmd" | sed 's/ --/-/g; s/ /-/g; s/--/-/g')
        fi

        label="${tool}/${method}"
        raw_file="$RAW_DIR/${fixture}-${tool}-${method}-${cmd_name}.json"

        echo "  $label: $cmd on $fixture..." >&2

        # Validate the command works before benchmarking
        if ! (cd "$tmp_dir" && eval "$full_cmd" >/dev/null 2>&1); then
          if [[ "$VERBOSE" == "true" ]]; then
            error_out=$(cd "$tmp_dir" && eval "$full_cmd" 2>&1 || true)
            echo "    SKIP: command failed: $error_out" >&2
          else
            echo "    SKIP: command failed" >&2
          fi
          continue
        fi

        hyperfine \
          --warmup "$WARMUP" \
          --runs "$RUNS" \
          --export-json "$raw_file" \
          --shell=bash \
          "cd $tmp_dir && $full_cmd >/dev/null 2>&1 || true" \
          2>/dev/null

        # Memory (single run)
        # shellcheck disable=SC2086
        mem=$(cd "$tmp_dir" && measure_memory $full_cmd 2>/dev/null || echo "N/A")
        echo "$mem" > "$RAW_DIR/${fixture}-${tool}-${method}-${cmd_name}.mem"
      done

      rm -rf "$tmp_dir" "${bare_remote:-}"
    done
  done
done

# Measure release-please install size (no runtime benchmark — requires GitHub API)
if ! $SKIP_COMPETITORS && command_exists npx; then
  echo "  Measuring release-please install size..." >&2
  rp_size=$(get_npm_size "release-please" 2>/dev/null || echo "N/A")
  echo "$rp_size" > "$RAW_DIR/release-please-npm-size.txt"
fi

# ---------------------------------------------------------------------------
# Aggregate results into latest.json
# ---------------------------------------------------------------------------

TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
FERRFLOW_VERSION=$(ferrflow --version 2>/dev/null | head -1 || echo "unknown")
FERRFLOW_BIN_SIZE=$(cat "$RAW_DIR/ferrflow-binary-size.txt" 2>/dev/null || echo "N/A")
FERRFLOW_NPM_SIZE=$(cat "$RAW_DIR/ferrflow-npm-size.txt" 2>/dev/null || echo "N/A")

{
  echo "{"
  echo "  \"timestamp\": \"$TIMESTAMP\","
  echo "  \"ferrflow_version\": \"$FERRFLOW_VERSION\","
  echo "  \"ferrflow_binary_size_mb\": \"$FERRFLOW_BIN_SIZE\","
  echo "  \"ferrflow_npm_size_mb\": \"$FERRFLOW_NPM_SIZE\","
  echo "  \"benchmarks\": {"

  first_bench=true
  for raw_file in "$RAW_DIR"/*.json; do
    [[ -f "$raw_file" ]] || continue
    basename=$(basename "$raw_file" .json)

    median=$(extract_median "$raw_file" 2>/dev/null || echo "0")
    stddev=$(extract_stddev "$raw_file" 2>/dev/null || echo "0")
    mem=$(cat "$RAW_DIR/${basename}.mem" 2>/dev/null || echo "N/A")

    if ! $first_bench; then echo ","; fi
    first_bench=false
    printf '    "%s": {"median_ms": %s, "stddev_ms": %s, "memory_mb": "%s"}' \
      "$basename" "$median" "$stddev" "$mem"
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
  for fixture in "${FIXTURES[@]}"; do
    echo ""
    echo "### ${fixture}"
    echo ""
    echo "| Tool | Method | Command | Median | Stddev | Memory (RSS) |"
    echo "|------|--------|---------|--------|--------|--------------|"

    for raw_file in "$RAW_DIR/${fixture}"-*.json; do
      [[ -f "$raw_file" ]] || continue
      basename=$(basename "$raw_file" .json)
      # Parse: fixture-tool-method-cmd
      rest="${basename#"${fixture}-"}"
      tool=$(echo "$rest" | cut -d'-' -f1)
      method=$(echo "$rest" | cut -d'-' -f2)
      cmd=$(echo "$rest" | cut -d'-' -f3-)

      median=$(extract_median "$raw_file" 2>/dev/null || echo "N/A")
      stddev=$(extract_stddev "$raw_file" 2>/dev/null || echo "N/A")
      mem=$(cat "$RAW_DIR/${basename}.mem" 2>/dev/null || echo "N/A")

      echo "| $tool | $method | $cmd | ${median}ms | ${stddev}ms | ${mem} MB |"
    done
  done
fi
