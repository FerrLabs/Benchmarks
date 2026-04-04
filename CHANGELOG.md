# Changelog

All notable changes to `benchmarks` will be documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

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
