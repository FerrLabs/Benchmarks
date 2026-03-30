# FerrFlow Benchmarks

[![CI](https://github.com/FerrFlow-Org/Benchmarks/actions/workflows/ci.yml/badge.svg)](https://github.com/FerrFlow-Org/Benchmarks/actions/workflows/ci.yml)
[![License](https://img.shields.io/github/license/FerrFlow-Org/Benchmarks)](LICENSE)

Reusable GitHub Action for running FerrFlow benchmarks and detecting performance regressions.

## Usage

```yaml
- uses: FerrFlow-Org/Benchmarks@v0
  with:
    type: micro        # micro, full, or all
    github-token: ${{ secrets.GITHUB_TOKEN }}
```

## Inputs

| Input | Description | Default |
|-------|-------------|---------|
| `type` | Benchmark type: `micro`, `full`, or `all` | `all` |
| `skip-competitors` | Skip competitor benchmarks in full mode | `false` |
| `alert-threshold` | Regression alert threshold (e.g. `120%`) | `120%` |
| `comment-on-pr` | Post benchmark results as PR comment | `true` |
| `github-token` | GitHub token for PR comments and artifact access | required |

## Outputs

| Output | Description |
|--------|-------------|
| `regression-detected` | `true` if a performance regression was detected |

## Benchmark types

### Micro (`micro`)

Runs criterion benchmarks (`cargo bench`) and compares against a stored baseline using [benchmark-action/github-action-benchmark](https://github.com/benchmark-action/github-action-benchmark).

- On PRs: downloads baseline artifact, compares, posts PR comment
- On main push: saves new baseline artifact

### Full (`full`)

Runs end-to-end benchmarks with [hyperfine](https://github.com/sharkdp/hyperfine) across multiple fixture sizes (single repo, mono-small, mono-medium, mono-large). Optionally compares against competitor tools (semantic-release, changesets, release-please).

- Generates fixtures using `cargo run --release --bin generate-fixtures`
- Measures execution time, memory usage, and binary size
- Compares against stored baseline and detects regressions (25% threshold)

## Requirements

The calling workflow must provide:

- Rust nightly toolchain (`dtolnay/rust-toolchain@nightly`)
- Rust cache (`Swatinem/rust-cache@v2`)
- Node.js (for full benchmarks with competitors): `actions/setup-node@v6`
- A project with `cargo bench --bench ferrflow_benchmarks` (for micro)
- A project with `cargo run --release --bin generate-fixtures` (for full)
