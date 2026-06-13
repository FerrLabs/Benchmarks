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

@test "does not emit redundant binary-size footer" {
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
  # Footer removed: the bench artifact's ferrflow_version is captured BEFORE
  # the release commit bumps the version, so it was always stale (e.g.
  # 4.8.1 in a 4.9.0 release). Binary size from the CI build also overstates
  # the real download. The Install footprint section is the canonical place
  # for size now; the release page already shows the version in its title.
  [[ "$output" != *"Binary size:"* ]]
  [[ "$output" != *"ferrflow 2.5.0"* ]]
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

@test "adds explanatory note when only ferrflow has Binary data" {
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
  [[ "$output" == *"### Binary"* ]]
  [[ "$output" == *"every competitor is a Node.js package"* ]]
}

@test "adds explanatory note when only ferrflow has Docker data" {
  cat > "$TMPDIR/latest.json" <<'EOF'
{
  "ferrflow_version": "2.5.0",
  "ferrflow_binary_size_mb": "5.2",
  "ferrflow_npm_size_mb": "N/A",
  "benchmarks": {
    "single-ferrflow-docker-check": {"median_ms": 184.5, "stddev_ms": 3.1, "memory_mb": "46.5"}
  }
}
EOF

  run bash "$SCRIPT_DIR/format-release.sh" "$TMPDIR/latest.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"### Docker"* ]]
  [[ "$output" == *"no competitor publishes a first-party Docker image"* ]]
}

@test "does not add the note when a competitor also has binary data" {
  cat > "$TMPDIR/latest.json" <<'EOF'
{
  "ferrflow_version": "2.5.0",
  "ferrflow_binary_size_mb": "5.2",
  "ferrflow_npm_size_mb": "N/A",
  "benchmarks": {
    "single-ferrflow-binary-check": {"median_ms": 14.7, "stddev_ms": 0.5, "memory_mb": "12.4"},
    "single-changesets-binary-check": {"median_ms": 50.0, "stddev_ms": 1.0, "memory_mb": "20.0"}
  }
}
EOF

  run bash "$SCRIPT_DIR/format-release.sh" "$TMPDIR/latest.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"### Binary"* ]]
  [[ "$output" != *"every competitor is a Node.js package"* ]]
}

@test "renders install footprint when install_sizes present" {
  cat > "$TMPDIR/latest.json" <<'EOF'
{
  "ferrflow_version": "2.5.0",
  "ferrflow_binary_size_mb": "5.2",
  "ferrflow_npm_size_mb": "1.1",
  "benchmarks": {
    "single-ferrflow-binary-check": {"median_ms": 14.7, "stddev_ms": 0.5, "memory_mb": "12.4"}
  },
  "install_sizes": {
    "ferrflow": {"binary": "5.2", "npm": "1.1"},
    "release-please": {"npm": "38.1"},
    "changesets": {"npm": "12.4"}
  }
}
EOF

  run bash "$SCRIPT_DIR/format-release.sh" "$TMPDIR/latest.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"### Install footprint"* ]]
  [[ "$output" == *"| release-please | 38.1 MB | — |"* ]]
  [[ "$output" == *"| ferrflow | 1.1 MB | 5.2 MB |"* ]]
}

@test "skips install footprint when install_sizes missing" {
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
  [[ "$output" != *"Install footprint"* ]]
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
