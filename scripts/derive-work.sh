#!/usr/bin/env bash
set -euo pipefail

# Split each benchmark cell into startup time and work time.
#
# Usage: ./derive-work.sh <latest.json> <floor-fixture-name> <output.json>
#
# The floor fixture is the smallest real job a tool can be given (one package,
# one commit since the last tag), run with each tool's normal command. Its
# median is therefore that tool's fixed cost of being invoked at all — process
# spawn, runtime boot, module loading, config resolution — on this runner.
#
#   work_ms = median_ms - startup_ms
#
# `--version` would be the obvious floor and it is wrong: it skips the lazy
# requires the real command pulls in, undercounting startup and billing the
# difference as the tool's work. Measured at ~286ms for commit-and-tag-version,
# and it flatters us, so the floor has to run the real command.
#
# Floor cells are removed from `benchmarks` — they are an instrument, not a
# data point, and the site would otherwise render `floor` as a fixture.
#
# Startup is real time the user waits, so median_ms stays untouched as the
# headline. This only explains where it goes.
#
# Requires: jq

INPUT="${1:-}"
FLOOR="${2:-}"
OUTPUT="${3:-}"

if [[ -z "$INPUT" || -z "$FLOOR" || -z "$OUTPUT" ]]; then
  echo "Usage: $0 <latest.json> <floor-fixture-name> <output.json>" >&2
  exit 2
fi

if [[ ! -f "$INPUT" ]]; then
  echo "Not a file: $INPUT" >&2
  exit 2
fi

mkdir -p "$(dirname "$OUTPUT")"

jq --arg floor "$FLOOR" '
  # Floor keys are "<floor>-<tool>-<method>-<cmd>"; benchmark keys are
  # "<fixture>-<tool>-<method>-<cmd>". Match a cell to its floor by the
  # "<tool>-<method>-<cmd>" tail, taking the longest match so a tool whose
  # name is a suffix of another cannot steal it.
  def floor_key($k; $startup):
    $startup | keys | map(. as $s | select($k | endswith("-" + $s))) | sort_by(length) | last;

  (.benchmarks // {}) as $all
  | ($all
     | to_entries
     | map(select(.key | startswith($floor + "-")))
     | map({key: (.key | ltrimstr($floor + "-")), value: .value})
     | from_entries) as $startup
  | .benchmarks = (
      $all
      | to_entries
      | map(select(.key | startswith($floor + "-") | not))
      | map(
          floor_key(.key; $startup) as $fk
          | if $fk == null then .
            else .value += {
                   startup_ms: $startup[$fk].median_ms,
                   work_ms: ([(.value.median_ms - $startup[$fk].median_ms), 0] | max)
                 }
            end
        )
      | from_entries
    )
' "$INPUT" > "$OUTPUT"

derived=$(jq '[.benchmarks[] | select(has("work_ms"))] | length' "$OUTPUT")
total=$(jq '.benchmarks | length' "$OUTPUT")
echo "Derived work_ms for $derived/$total cell(s) in $OUTPUT" >&2
