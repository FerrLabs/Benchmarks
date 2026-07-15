# FerrFlow Benchmarks

[![License](https://img.shields.io/github/license/FerrLabs/Benchmarks)](LICENSE)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/FerrLabs/Benchmarks/badge)](https://scorecard.dev/viewer/?uri=github.com/FerrLabs/Benchmarks)

Reusable GitHub Action for running FerrFlow benchmarks and detecting performance regressions.

## Usage

```yaml
- uses: FerrLabs/Benchmarks@v2
  with:
    type: micro        # micro, full, or all
    ferrflow-token: ${{ secrets.FERRFLOW_TOKEN }}
```

## Inputs

| Input | Description | Default |
|-------|-------------|---------|
| `type` | Benchmark type: `micro`, `full`, or `all` | `all` |
| `skip-competitors` | Skip competitor benchmarks in full mode | `false` |
| `alert-threshold` | Regression alert threshold for micro benchmarks (e.g. `120%`) | `120%` |
| `full-regression-threshold` | Relative threshold for full benchmark regressions (e.g. `125%`) | `125%` |
| `binary-size-threshold` | Binary size growth threshold (e.g. `120%`) | `120%` |
| `comment-on-pr` | Post benchmark results as PR comment | `true` |
| `warmup` | Number of warmup runs before timing (hyperfine `--warmup`) | `2` |
| `runs` | Number of timed runs (hyperfine `--runs`) | `10` |
| `definitions` | Path to fixture definitions for benchmark generation | required |
| `verbose` | Show full error output when a benchmark command fails validation | `false` |
| `ferrflow-token` | GitHub token for PR comments and artifact access | required |
| `group-filter` | Criterion bench group filter (substring) for micro matrix sharding | `''` |
| `binary-dir` | Directory holding a prebuilt `ferrflow` executable. When set, the full benchmark skips its own `cargo build --release` and puts this directory on PATH | `''` |
| `fixtures-dir` | Directory of already-generated fixtures. When set, the full benchmark skips its own generation | `''` |
| `shard` | Run as a matrix shard: benchmark and write `latest.json`, skip baseline/compare/comment/uploads | `false` |
| `merge-partials` | Directory of partial `latest.json` files. When set, skip building and benchmarking; merge the partials, then compare and upload over the merged result | `''` |

### Sharding the full benchmark

The full benchmark runs every fixture sequentially, so wall-clock is the sum of
them all. To spread it over runners, generate the fixtures once, run one shard
per fixture, then aggregate:

1. **Shards** — one job per fixture, each with `shard: true`, a `fixtures-dir`
   holding only its own fixture, and `binary-dir` pointing at a prebuilt
   binary. Each uploads its `benchmarks/results/latest.json` as a partial.
2. **Aggregate** — one job that downloads every partial into a directory and
   passes it as `merge-partials`. It merges them and runs the regression check,
   PR comment and uploads once, over the whole result.

Shard per **fixture**, never per tool: the comparison ferrflow-vs-competitors
only means something when both ran on the same machine. Per-fixture shards keep
each comparison inside one runner; only absolute numbers *between* fixtures come
from different hardware.

## Outputs

| Output | Description |
|--------|-------------|
| `regression-detected` | `true` if a performance regression was detected |
| `benchmark-summary` | Formatted benchmark summary (markdown) for release notes |

## Benchmark types

### Micro (`micro`)

Runs criterion benchmarks (`cargo bench`) and compares against a stored baseline using [benchmark-action/github-action-benchmark](https://github.com/benchmark-action/github-action-benchmark).

- On PRs: downloads baseline artifact, compares, posts PR comment
- On main push: saves new baseline artifact

### Full (`full`)

Runs end-to-end benchmarks with [hyperfine](https://github.com/sharkdp/hyperfine) across multiple fixture sizes (single repo, mono-small, mono-medium, mono-large). Optionally compares against competitor tools (semantic-release, changesets, release-please).

- Generates fixtures via the [`FerrLabs/Fixtures`](https://github.com/FerrLabs/Fixtures) action from the JSON `definitions` directory you pass
- Measures execution time, memory usage, and binary size
- Compares against stored baseline and detects regressions (configurable threshold, default 25%)

## Requirements

The calling workflow must provide:

- Rust nightly toolchain (`dtolnay/rust-toolchain@nightly`)
- Rust cache (`Swatinem/rust-cache@v2`)
- Node.js (for full benchmarks with competitors): `actions/setup-node@v6`
- A project with `cargo bench --bench ferrflow_benchmarks` (for micro)
- A directory of JSON fixture definitions, passed via the `definitions` input — the action generates the fixtures with [`FerrLabs/Fixtures`](https://github.com/FerrLabs/Fixtures) (for full)
- A project that builds a release binary with `cargo build --release` — the action puts `target/release` on `PATH` and benchmarks it (for full)
