#!/usr/bin/env bats

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts"

setup() {
  TMPDIR="$(mktemp -d)"
  mkdir -p "$TMPDIR/partials"
}

teardown() {
  rm -rf "$TMPDIR"
}

make_partial() {
  local file="$1" benchmarks="$2" parallel="${3:-}" sizes="${4:-}"
  cat > "$file" <<EOF
{
  "timestamp": "2026-07-15T00:00:00Z",
  "ferrflow_version": "ferrflow 5.29.0",
  "ferrflow_binary_size_mb": "9.0",
  "runner_cores": 4,
  "benchmarks": {$benchmarks},
  "ferrflow_parallel": {$parallel},
  "install_sizes": {$sizes}
}
EOF
}

@test "unions benchmarks from every shard" {
  make_partial "$TMPDIR/partials/single.json" \
    '"single-ferrflow-binary-check": {"median_ms": 10.0, "stddev_ms": 0.5, "memory_mb": "12.4"}'
  make_partial "$TMPDIR/partials/complex.json" \
    '"complex-ferrflow-binary-check": {"median_ms": 42.0, "stddev_ms": 1.5, "memory_mb": "30.1"}'

  run "$SCRIPT_DIR/merge-results.sh" "$TMPDIR/partials" "$TMPDIR/latest.json"
  [ "$status" -eq 0 ]

  [ "$(jq '.benchmarks | length' "$TMPDIR/latest.json")" -eq 2 ]
  [ "$(jq -r '.benchmarks["single-ferrflow-binary-check"].median_ms' "$TMPDIR/latest.json")" = "10" ]
  [ "$(jq -r '.benchmarks["complex-ferrflow-binary-check"].median_ms' "$TMPDIR/latest.json")" = "42" ]
}

@test "keeps run-level metadata" {
  make_partial "$TMPDIR/partials/a.json" '"a-ferrflow-binary-check": {"median_ms": 1.0}'
  make_partial "$TMPDIR/partials/b.json" '"b-ferrflow-binary-check": {"median_ms": 2.0}'

  run "$SCRIPT_DIR/merge-results.sh" "$TMPDIR/partials" "$TMPDIR/latest.json"
  [ "$status" -eq 0 ]

  [ "$(jq -r '.ferrflow_version' "$TMPDIR/latest.json")" = "ferrflow 5.29.0" ]
  [ "$(jq -r '.ferrflow_binary_size_mb' "$TMPDIR/latest.json")" = "9.0" ]
  [ "$(jq -r '.runner_cores' "$TMPDIR/latest.json")" = "4" ]
}

@test "merges ferrflow_parallel and install_sizes too" {
  make_partial "$TMPDIR/partials/a.json" '"a-ferrflow-binary-check": {"median_ms": 1.0}' \
    '"a-jobs-4": {"median_ms": 5.0}' '"ferrflow": "9.0"'
  make_partial "$TMPDIR/partials/b.json" '"b-ferrflow-binary-check": {"median_ms": 2.0}' \
    '"b-jobs-4": {"median_ms": 6.0}' '"changesets": "1.2"'

  run "$SCRIPT_DIR/merge-results.sh" "$TMPDIR/partials" "$TMPDIR/latest.json"
  [ "$status" -eq 0 ]

  [ "$(jq '.ferrflow_parallel | length' "$TMPDIR/latest.json")" -eq 2 ]
  [ "$(jq '.install_sizes | length' "$TMPDIR/latest.json")" -eq 2 ]
}

@test "a single shard round-trips unchanged" {
  make_partial "$TMPDIR/partials/only.json" '"only-ferrflow-binary-check": {"median_ms": 7.0}'

  run "$SCRIPT_DIR/merge-results.sh" "$TMPDIR/partials" "$TMPDIR/latest.json"
  [ "$status" -eq 0 ]
  [ "$(jq '.benchmarks | length' "$TMPDIR/latest.json")" -eq 1 ]
}

@test "fails when no partials are present" {
  run "$SCRIPT_DIR/merge-results.sh" "$TMPDIR/partials" "$TMPDIR/latest.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"No partial result files"* ]]
}

@test "fails on a missing partials directory" {
  run "$SCRIPT_DIR/merge-results.sh" "$TMPDIR/nope" "$TMPDIR/latest.json"
  [ "$status" -eq 2 ]
}

@test "tolerates a shard that produced no benchmarks" {
  make_partial "$TMPDIR/partials/a.json" '"a-ferrflow-binary-check": {"median_ms": 1.0}'
  echo '{"ferrflow_version": "ferrflow 5.29.0"}' > "$TMPDIR/partials/empty.json"

  run "$SCRIPT_DIR/merge-results.sh" "$TMPDIR/partials" "$TMPDIR/latest.json"
  [ "$status" -eq 0 ]
  [ "$(jq '.benchmarks | length' "$TMPDIR/latest.json")" -eq 1 ]
}
