# Changelog

All notable changes to `benchmarks` will be documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [3.0.2] - 2026-04-19

### Bug Fixes

- fix(micro): tolerate cargo bench non-zero exit when rows were captured (#91)

## [3.0.1] - 2026-04-19

### Bug Fixes

- fix(micro): filter orphan 'bench:' lines before piping to benchmark-action (#90)

## [3.0.0] - 2026-04-15

### Breaking Changes

- chore!: switch license from MIT to MPL-2.0 (#87)

## [2.8.1] - 2026-04-11

### Bug Fixes

- fix: validate memory measurement is numeric before display (#86)

## [2.8.0] - 2026-04-10

### Features

- feat: restructure benchmark tables to pivot layout grouped by method (#84)

## [2.7.0] - 2026-04-10

### Features

- feat: add validate command to ferrflow benchmarks (#83)

## [2.6.0] - 2026-04-10

### Features

- feat: use equal warmup and runs for all tools with configurable inputs (#82)

## [2.5.7] - 2026-04-10

### Bug Fixes

- fix: use jq to build latest.json instead of string concatenation (#81)

## [2.5.6] - 2026-04-10

### Bug Fixes

- fix: warn when absolute threshold keys don't match any benchmark (#80)

## [2.5.5] - 2026-04-10

### Bug Fixes

- fix: remove || true from hyperfine command to avoid timing failed runs (#79)

## [2.5.4] - 2026-04-10

### Bug Fixes

- fix(ci): remove debug telemetry step from release job (#77)

## [2.5.3] - 2026-04-06

### Bug Fixes

- fix: resolve changesets workspace resolution and semantic-release token check (#75)

## [2.5.2] - 2026-04-05

### Bug Fixes

- fix: resolve benchmark SKIP failures for competitors and ferrflow subcommands (#67)

## [2.5.1] - 2026-04-04

### Bug Fixes

- fix: parse benchmark keys into proper table columns (#64)

## [2.5.0] - 2026-04-04

### Features

- feat: benchmark tool_configs and disable skipCi (#63)

## [2.4.0] - 2026-04-04

### Features

- feat: refactor benchmarks to use tools.json and tool_configs from definitions (#62)

## [2.3.5] - 2026-04-04

### Bug Fixes

- fix: suppress shellcheck SC2015 for benchmark memory measurement (#60)
- fix: tolerate non-zero exit codes in benchmarked commands (#59)

## [2.3.4] - 2026-04-04

### Bug Fixes

- fix: create results directory before running benchmarks (#57)

## [2.3.3] - 2026-04-04

### Bug Fixes

- fix(ci): add FERRFLOW_TOKEN env var to release job (#55)

## [2.3.2] - 2026-04-04

### Bug Fixes

- fix: create empty micro baseline when artifact is missing (#51)

## [2.3.1] - 2026-04-01

### Bug Fixes

- fix(scripts): fix competitor benchmark validation failures (#46)

## [2.3.0] - 2026-04-01

### Features

- feat: benchmark competitors on mono-large fixture (#44)

## [2.2.4] - 2026-04-01

### Bug Fixes

- fix(action): remove timeout-minutes unsupported in composite actions (#43)

## [2.2.3] - 2026-04-01

### Bug Fixes

- fix(bench): remove --max-runs conflicting with --runs in hyperfine (#42)

## [2.2.2] - 2026-04-01

### Bug Fixes

- fix(bench): replace invalid --time-limit with --max-runs for hyperfine (#41)

## [2.2.1] - 2026-04-01

### Bug Fixes

- fix(ci): add timeout-minutes to benchmark steps and --time-limit to hyperfine (#40)

## [2.2.0] - 2026-03-31

### Features

- feat: include competitor comparison in release summary (#38)

## [2.1.0] - 2026-03-31

### Features

- feat: expose full benchmark regression thresholds as action inputs (#32)
- feat: expose benchmark summary as action output for release notes (#34)
- feat(ci): include benchmark results in releases and step summary (#31)

### Bug Fixes

- fix(ci): repair YAML syntax in release benchmark step (#35)

## [2.0.2] - 2026-03-31

### Bug Fixes

- fix(scripts): validate competitor commands before benchmarking (#28)

## [2.0.1] - 2026-03-31

### Bug Fixes

- fix: surface missing baseline in PR comment (#19)

## [2.0.0] - 2026-03-31

### Breaking Changes

- feat!: rename github-token input to ferrflow-token

## [1.0.0] - 2026-03-31

### Breaking Changes

- chore!: switch license from MIT to MPL-2.0 (#2)

### Features

- feat(action): post full benchmark results as PR comment (#18)
- feat: add release workflow with FerrFlow and major tag update (#16)
- feat: add reusable benchmark action

### Bug Fixes

- fix: add VERSION file so FerrFlow can track releases (#17)
- fix: set git identity for benchmark steps (#14)
