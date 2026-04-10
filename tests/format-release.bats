#!/usr/bin/env bats

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts"

setup() {
  TMPDIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMPDIR"
}

@test "produces pivot table grouped by method" {
  cat > "$TMPDIR/latest.json" <<'EOF'
{
  "ferrflow_version": "2.5.0",
  "ferrflow_binary_size_mb": "5.2",
  "ferrflow_npm_size_mb": "N/A",
  "benchmarks": {
    "single-ferrflow-binary-check": {"median_ms": 14.7, "stddev_ms": 0.5, "memory_mb": "12.4"},
    "single-ferrflow-binary-version": {"median_ms": 10.8, "stddev_ms": 0.3, "memory_mb": "12.4"}
  }
}
EOF

  run bash "$SCRIPT_DIR/format-release.sh" "$TMPDIR/latest.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"## Performance"* ]]
  [[ "$output" == *"### Binary"* ]]
  [[ "$output" == *"| Fixture | Tool |"* ]]
  [[ "$output" == *"14.7ms"* ]]
  [[ "$output" == *"10.8ms"* ]]
  [[ "$output" == *"12.4 MB"* ]]
}

@test "shows binary size and version in footer" {
  cat > "$TMPDIR/latest.json" <<'EOF'
{
  "ferrflow_version": "2.5.0",
  "ferrflow_binary_size_mb": "5.2",
  "ferrflow_npm_size_mb": "N/A",
  "benchmarks": {
    "single-ferrflow-binary-check": {"median_ms": 14.7, "stddev_ms": 0.5, "memory_mb": "12.4"}
  }
}
EOF

  run bash "$SCRIPT_DIR/format-release.sh" "$TMPDIR/latest.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Binary size: 5.2 MB"* ]]
  [[ "$output" == *"ferrflow 2.5.0"* ]]
}

@test "shows delta percentages with baseline" {
  cat > "$TMPDIR/baseline.json" <<'EOF'
{
  "ferrflow_version": "2.4.0",
  "ferrflow_binary_size_mb": "5.0",
  "ferrflow_npm_size_mb": "N/A",
  "benchmarks": {
    "single-ferrflow-binary-check": {"median_ms": 20.0, "stddev_ms": 0.5, "memory_mb": "12.4"}
  }
}
EOF
  cat > "$TMPDIR/latest.json" <<'EOF'
{
  "ferrflow_version": "2.5.0",
  "ferrflow_binary_size_mb": "5.2",
  "ferrflow_npm_size_mb": "N/A",
  "benchmarks": {
    "single-ferrflow-binary-check": {"median_ms": 14.7, "stddev_ms": 0.5, "memory_mb": "12.4"}
  }
}
EOF

  run bash "$SCRIPT_DIR/format-release.sh" "$TMPDIR/latest.json" --with-delta "$TMPDIR/baseline.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"(-"*"%)"* ]]
}

@test "handles multiple methods" {
  cat > "$TMPDIR/latest.json" <<'EOF'
{
  "ferrflow_version": "2.5.0",
  "ferrflow_binary_size_mb": "5.2",
  "ferrflow_npm_size_mb": "1.1",
  "benchmarks": {
    "single-ferrflow-binary-check": {"median_ms": 14.7, "stddev_ms": 0.5, "memory_mb": "12.4"},
    "single-ferrflow-npm-check": {"median_ms": 114.7, "stddev_ms": 2.5, "memory_mb": "32.4"}
  }
}
EOF

  run bash "$SCRIPT_DIR/format-release.sh" "$TMPDIR/latest.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"### Binary"* ]]
  [[ "$output" == *"### Npm"* ]]
}

@test "handles empty benchmarks" {
  cat > "$TMPDIR/latest.json" <<'EOF'
{
  "ferrflow_version": "2.5.0",
  "ferrflow_binary_size_mb": "N/A",
  "ferrflow_npm_size_mb": "N/A",
  "benchmarks": {}
}
EOF

  run bash "$SCRIPT_DIR/format-release.sh" "$TMPDIR/latest.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"## Performance"* ]]
  [[ "$output" == *"Binary size: N/A MB"* ]]
}

@test "exits 1 with no arguments" {
  run bash "$SCRIPT_DIR/format-release.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage"* ]]
}

@test "handles multiple tools per fixture" {
  cat > "$TMPDIR/latest.json" <<'EOF'
{
  "ferrflow_version": "2.5.0",
  "ferrflow_binary_size_mb": "5.2",
  "ferrflow_npm_size_mb": "N/A",
  "benchmarks": {
    "single-ferrflow-binary-check": {"median_ms": 14.7, "stddev_ms": 0.5, "memory_mb": "12.4"},
    "single-semantic-release-npm-check": {"median_ms": 500.0, "stddev_ms": 10.0, "memory_mb": "80.0"}
  }
}
EOF

  run bash "$SCRIPT_DIR/format-release.sh" "$TMPDIR/latest.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ferrflow"* ]]
  [[ "$output" == *"semantic-release"* ]]
}
