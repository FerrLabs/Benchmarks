#!/usr/bin/env bash
set -euo pipefail

# Merge partial benchmark results from sharded runs into one latest.json
#
# Usage: ./merge-results.sh <partials-dir> <output.json>
#
# Each shard benchmarks a distinct fixture, so the `benchmarks`,
# `ferrflow_parallel`, `ferrflow_cached` and `install_sizes` maps are keyed by
# fixture and never collide — merging them is a plain union. Run-level metadata
# (version, binary sizes, runner_cores, warmup, runs) is taken from the first
# partial: every shard benchmarks the same binary with the same settings, and
# shards run on identically-specced runners.
#
# Requires: jq

PARTIALS_DIR="${1:-}"
OUTPUT="${2:-}"

if [[ -z "$PARTIALS_DIR" || -z "$OUTPUT" ]]; then
  echo "Usage: $0 <partials-dir> <output.json>" >&2
  exit 2
fi

if [[ ! -d "$PARTIALS_DIR" ]]; then
  echo "Not a directory: $PARTIALS_DIR" >&2
  exit 2
fi

files=()
while IFS= read -r f; do
  files+=("$f")
done < <(find "$PARTIALS_DIR" -type f -name '*.json' | sort)

if [[ ${#files[@]} -eq 0 ]]; then
  echo "No partial result files (*.json) found under $PARTIALS_DIR" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT")"

jq -s '
  .[0]
  + {
      benchmarks: (map(.benchmarks // {}) | add),
      ferrflow_parallel: (map(.ferrflow_parallel // {}) | add),
      ferrflow_cached: (map(.ferrflow_cached // {}) | add),
      install_sizes: (map(.install_sizes // {}) | add)
    }
' "${files[@]}" > "$OUTPUT"

count=$(jq '.benchmarks | length' "$OUTPUT")
echo "Merged ${#files[@]} partial(s) into $OUTPUT ($count benchmark entries)" >&2
