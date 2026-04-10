#!/usr/bin/env bats

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts"

setup() {
  TMPDIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMPDIR"
}

make_json() {
  local file="$1"
  shift
  local benchmarks="$*"
  cat > "$file" <<EOF
{
  "ferrflow_version": "2.5.0",
  "ferrflow_binary_size_mb": "5.2",
  "ferrflow_npm_size_mb": "N/A",
  "benchmarks": {$benchmarks}
}
EOF
}

@test "exits 0 when no regressions" {
  make_json "$TMPDIR/baseline.json" \
    '"single-ferrflow-binary-check": {"median_ms": 10.0, "stddev_ms": 0.5, "memory_mb": "12.4"}'
  make_json "$TMPDIR/latest.json" \
    '"single-ferrflow-binary-check": {"median_ms": 10.5, "stddev_ms": 0.5, "memory_mb": "12.4"}'

  run bash "$SCRIPT_DIR/compare.sh" "$TMPDIR/baseline.json" "$TMPDIR/latest.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"All benchmarks within thresholds"* ]]
}

@test "exits 1 when regression exceeds relative threshold" {
  make_json "$TMPDIR/baseline.json" \
    '"single-ferrflow-binary-check": {"median_ms": 10.0, "stddev_ms": 0.5, "memory_mb": "12.4"}'
  make_json "$TMPDIR/latest.json" \
    '"single-ferrflow-binary-check": {"median_ms": 15.0, "stddev_ms": 0.5, "memory_mb": "12.4"}'

  run bash "$SCRIPT_DIR/compare.sh" "$TMPDIR/baseline.json" "$TMPDIR/latest.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL"* ]]
  [[ "$output" == *"REGRESSION DETECTED"* ]]
}

@test "exits 0 with no-baseline status when baseline missing" {
  make_json "$TMPDIR/latest.json" \
    '"single-ferrflow-binary-check": {"median_ms": 10.0, "stddev_ms": 0.5, "memory_mb": "12.4"}'

  run bash "$SCRIPT_DIR/compare.sh" "$TMPDIR/nonexistent.json" "$TMPDIR/latest.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"status=no-baseline"* ]]
}

@test "exits 1 when latest file missing" {
  make_json "$TMPDIR/baseline.json" \
    '"single-ferrflow-binary-check": {"median_ms": 10.0, "stddev_ms": 0.5, "memory_mb": "12.4"}'

  run bash "$SCRIPT_DIR/compare.sh" "$TMPDIR/baseline.json" "$TMPDIR/nonexistent.json"
  [ "$status" -eq 1 ]
}

@test "marks new benchmarks without baseline data" {
  make_json "$TMPDIR/baseline.json" '{}'
  make_json "$TMPDIR/latest.json" \
    '"single-ferrflow-binary-check": {"median_ms": 10.0, "stddev_ms": 0.5, "memory_mb": "12.4"}'

  run bash "$SCRIPT_DIR/compare.sh" "$TMPDIR/baseline.json" "$TMPDIR/latest.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"NEW"* ]]
  [[ "$output" == *"no baseline"* ]]
}

@test "custom threshold via FULL_REGRESSION_THRESHOLD" {
  make_json "$TMPDIR/baseline.json" \
    '"single-ferrflow-binary-check": {"median_ms": 10.0, "stddev_ms": 0.5, "memory_mb": "12.4"}'
  make_json "$TMPDIR/latest.json" \
    '"single-ferrflow-binary-check": {"median_ms": 11.0, "stddev_ms": 0.5, "memory_mb": "12.4"}'

  # 10% increase with 105% threshold should fail
  FULL_REGRESSION_THRESHOLD="105%" run bash "$SCRIPT_DIR/compare.sh" "$TMPDIR/baseline.json" "$TMPDIR/latest.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL"* ]]
}

@test "absolute threshold triggers FAIL" {
  make_json "$TMPDIR/baseline.json" '{}'
  make_json "$TMPDIR/latest.json" \
    '"mono-large-ferrflow-binary-check": {"median_ms": 2500.0, "stddev_ms": 10, "memory_mb": "21.5"}'

  run bash "$SCRIPT_DIR/compare.sh" "$TMPDIR/baseline.json" "$TMPDIR/latest.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL"*"exceeds absolute limit"* ]]
}

@test "absolute threshold passes when under limit" {
  make_json "$TMPDIR/baseline.json" '{}'
  make_json "$TMPDIR/latest.json" \
    '"mono-large-ferrflow-binary-check": {"median_ms": 1500.0, "stddev_ms": 10, "memory_mb": "21.5"}'

  run bash "$SCRIPT_DIR/compare.sh" "$TMPDIR/baseline.json" "$TMPDIR/latest.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"*"(limit:"* ]]
}

@test "warns when absolute threshold key has no match" {
  make_json "$TMPDIR/baseline.json" \
    '"single-ferrflow-binary-check": {"median_ms": 10.0, "stddev_ms": 0.5, "memory_mb": "12.4"}'
  make_json "$TMPDIR/latest.json" \
    '"single-ferrflow-binary-check": {"median_ms": 10.0, "stddev_ms": 0.5, "memory_mb": "12.4"}'

  run bash "$SCRIPT_DIR/compare.sh" "$TMPDIR/baseline.json" "$TMPDIR/latest.json" 2>&1
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN"*"no matching benchmark"* ]]
}

@test "binary size regression detection" {
  cat > "$TMPDIR/baseline.json" <<EOF
{
  "ferrflow_version": "2.4.0",
  "ferrflow_binary_size_mb": "5.0",
  "ferrflow_npm_size_mb": "N/A",
  "benchmarks": {}
}
EOF
  cat > "$TMPDIR/latest.json" <<EOF
{
  "ferrflow_version": "2.5.0",
  "ferrflow_binary_size_mb": "7.0",
  "ferrflow_npm_size_mb": "N/A",
  "benchmarks": {}
}
EOF

  run bash "$SCRIPT_DIR/compare.sh" "$TMPDIR/baseline.json" "$TMPDIR/latest.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL binary size"* ]]
}

@test "skips non-ferrflow benchmarks in relative checks" {
  make_json "$TMPDIR/baseline.json" \
    '"single-changesets-npm-check": {"median_ms": 10.0, "stddev_ms": 0.5, "memory_mb": "50"}'
  make_json "$TMPDIR/latest.json" \
    '"single-changesets-npm-check": {"median_ms": 100.0, "stddev_ms": 0.5, "memory_mb": "50"}'

  run bash "$SCRIPT_DIR/compare.sh" "$TMPDIR/baseline.json" "$TMPDIR/latest.json"
  [ "$status" -eq 0 ]
  [[ "$output" != *"FAIL"* ]]
}

@test "exits 1 when no arguments" {
  run bash "$SCRIPT_DIR/compare.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage"* ]]
}
