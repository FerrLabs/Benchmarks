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
  "warmup": 2,
  "runs": 30,
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
  # Compare numerically: jq versions differ on whether 10.0 prints as "10".
  [ "$(jq '.benchmarks["single-ferrflow-binary-check"].median_ms == 10' "$TMPDIR/latest.json")" = "true" ]
  [ "$(jq '.benchmarks["complex-ferrflow-binary-check"].median_ms == 42' "$TMPDIR/latest.json")" = "true" ]
}

@test "keeps run-level metadata" {
  make_partial "$TMPDIR/partials/a.json" '"a-ferrflow-binary-check": {"median_ms": 1.0}'
  make_partial "$TMPDIR/partials/b.json" '"b-ferrflow-binary-check": {"median_ms": 2.0}'

  run "$SCRIPT_DIR/merge-results.sh" "$TMPDIR/partials" "$TMPDIR/latest.json"
  [ "$status" -eq 0 ]

  [ "$(jq -r '.ferrflow_version' "$TMPDIR/latest.json")" = "ferrflow 5.29.0" ]
  [ "$(jq -r '.ferrflow_binary_size_mb' "$TMPDIR/latest.json")" = "9.0" ]
  [ "$(jq -r '.runner_cores' "$TMPDIR/latest.json")" = "4" ]
  # The site renders these, so they have to survive the merge.
  [ "$(jq -r '.warmup' "$TMPDIR/latest.json")" = "2" ]
  [ "$(jq -r '.runs' "$TMPDIR/latest.json")" = "30" ]
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

@test "merges the warm-cache stat across shards" {
  cat > "$TMPDIR/partials/a.json" <<'EOF'
{"benchmarks":{"a-ferrflow-binary-check":{"median_ms":21.0}},
 "ferrflow_cached":{"a-check":{"median_ms":3.0}}}
EOF
  cat > "$TMPDIR/partials/b.json" <<'EOF'
{"benchmarks":{"b-ferrflow-binary-check":{"median_ms":740.0}},
 "ferrflow_cached":{"b-check":{"median_ms":5.0}}}
EOF

  run "$SCRIPT_DIR/merge-results.sh" "$TMPDIR/partials" "$TMPDIR/latest.json"
  [ "$status" -eq 0 ]

  [ "$(jq '.ferrflow_cached | length' "$TMPDIR/latest.json")" -eq 2 ]
  [ "$(jq '.ferrflow_cached["b-check"].median_ms == 5' "$TMPDIR/latest.json")" = "true" ]
  # The cold number stays the headline; the warm one must not leak into it.
  [ "$(jq '.benchmarks["b-ferrflow-binary-check"].median_ms == 740' "$TMPDIR/latest.json")" = "true" ]
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
