#!/usr/bin/env bats

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts"

setup() { TMPDIR="$(mktemp -d)"; }
teardown() { rm -rf "$TMPDIR"; }

write_input() {
  cat > "$TMPDIR/latest.json"
}

run_derive() {
  run "$SCRIPT_DIR/derive-work.sh" "$TMPDIR/latest.json" floor "$TMPDIR/out.json"
}

@test "splits a cell into startup and work using the floor" {
  write_input <<'EOF'
{"benchmarks":{
  "floor-changesets-npm-check":     {"median_ms": 700.0},
  "mono-large-changesets-npm-check":{"median_ms": 990.0}
}}
EOF
  run_derive
  [ "$status" -eq 0 ]
  [ "$(jq '.benchmarks["mono-large-changesets-npm-check"].startup_ms == 700' "$TMPDIR/out.json")" = "true" ]
  [ "$(jq '.benchmarks["mono-large-changesets-npm-check"].work_ms == 290' "$TMPDIR/out.json")" = "true" ]
}

# The floor is an instrument, not a data point; leaving it in would render as a
# fixture on the site.
@test "drops floor cells from benchmarks" {
  write_input <<'EOF'
{"benchmarks":{
  "floor-ferrflow-binary-check":  {"median_ms": 5.0},
  "single-ferrflow-binary-check": {"median_ms": 25.0}
}}
EOF
  run_derive
  [ "$status" -eq 0 ]
  [ "$(jq '.benchmarks | has("floor-ferrflow-binary-check")' "$TMPDIR/out.json")" = "false" ]
  [ "$(jq '.benchmarks | length' "$TMPDIR/out.json")" -eq 1 ]
}

@test "median_ms stays the headline and is never rewritten" {
  write_input <<'EOF'
{"benchmarks":{
  "floor-changesets-npm-check":     {"median_ms": 700.0},
  "mono-large-changesets-npm-check":{"median_ms": 990.0, "memory_mb": "40.0"}
}}
EOF
  run_derive
  [ "$status" -eq 0 ]
  [ "$(jq '.benchmarks["mono-large-changesets-npm-check"].median_ms == 990' "$TMPDIR/out.json")" = "true" ]
  [ "$(jq -r '.benchmarks["mono-large-changesets-npm-check"].memory_mb' "$TMPDIR/out.json")" = "40.0" ]
}

# A tool faster than its own floor is noise, not negative work.
@test "clamps work at zero when a cell lands under the floor" {
  write_input <<'EOF'
{"benchmarks":{
  "floor-changesets-npm-check":  {"median_ms": 700.0},
  "single-changesets-npm-check": {"median_ms": 690.0}
}}
EOF
  run_derive
  [ "$status" -eq 0 ]
  [ "$(jq '.benchmarks["single-changesets-npm-check"].work_ms == 0' "$TMPDIR/out.json")" = "true" ]
}

# Each tool/method/command has its own floor — a binary's startup is not npx's.
@test "matches each cell to its own tool, method and command" {
  write_input <<'EOF'
{"benchmarks":{
  "floor-ferrflow-binary-check":         {"median_ms": 5.0},
  "floor-ferrflow-npm-check":            {"median_ms": 600.0},
  "floor-ferrflow-binary-release-dry-run":{"median_ms": 8.0},
  "mono-large-ferrflow-binary-check":    {"median_ms": 1155.0},
  "mono-large-ferrflow-npm-check":       {"median_ms": 1750.0},
  "mono-large-ferrflow-binary-release-dry-run":{"median_ms": 1200.0}
}}
EOF
  run_derive
  [ "$status" -eq 0 ]
  [ "$(jq '.benchmarks["mono-large-ferrflow-binary-check"].work_ms == 1150' "$TMPDIR/out.json")" = "true" ]
  [ "$(jq '.benchmarks["mono-large-ferrflow-npm-check"].work_ms == 1150' "$TMPDIR/out.json")" = "true" ]
  [ "$(jq '.benchmarks["mono-large-ferrflow-binary-release-dry-run"].work_ms == 1192' "$TMPDIR/out.json")" = "true" ]
}

# Without a floor run there is nothing to subtract; the cell must still ship.
@test "leaves a cell untouched when its floor is missing" {
  write_input <<'EOF'
{"benchmarks":{
  "floor-ferrflow-binary-check":     {"median_ms": 5.0},
  "single-semantic-release-npm-check":{"median_ms": 800.0}
}}
EOF
  run_derive
  [ "$status" -eq 0 ]
  [ "$(jq '.benchmarks["single-semantic-release-npm-check"] | has("work_ms")' "$TMPDIR/out.json")" = "false" ]
  [ "$(jq '.benchmarks["single-semantic-release-npm-check"].median_ms == 800' "$TMPDIR/out.json")" = "true" ]
}

# A shard that never ran the floor still has to produce usable output.
@test "no floor cells at all is a passthrough" {
  write_input <<'EOF'
{"benchmarks":{"single-ferrflow-binary-check":{"median_ms": 25.0}},"runner_cores":4}
EOF
  run_derive
  [ "$status" -eq 0 ]
  [ "$(jq '.benchmarks | length' "$TMPDIR/out.json")" -eq 1 ]
  [ "$(jq '.runner_cores' "$TMPDIR/out.json")" -eq 4 ]
}

@test "run-level metadata survives" {
  write_input <<'EOF'
{"ferrflow_version":"ferrflow 5.29.4","warmup":3,"runs":30,
 "benchmarks":{"floor-ferrflow-binary-check":{"median_ms":5.0},
               "single-ferrflow-binary-check":{"median_ms":25.0}},
 "ferrflow_cached":{"single-check":{"median_ms":3.0}}}
EOF
  run_derive
  [ "$status" -eq 0 ]
  [ "$(jq -r '.ferrflow_version' "$TMPDIR/out.json")" = "ferrflow 5.29.4" ]
  [ "$(jq '.warmup' "$TMPDIR/out.json")" -eq 3 ]
  [ "$(jq '.ferrflow_cached["single-check"].median_ms == 3' "$TMPDIR/out.json")" = "true" ]
}

@test "fails on a missing input file" {
  run "$SCRIPT_DIR/derive-work.sh" "$TMPDIR/nope.json" floor "$TMPDIR/out.json"
  [ "$status" -eq 2 ]
}
