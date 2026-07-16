#!/usr/bin/env bats

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts"

setup() {
  TMPDIR="$(mktemp -d)"
  FX="$TMPDIR/fx"
  mkdir -p "$FX/.changeset"
  git -C "$FX" init -q -b main 2>/dev/null || (mkdir -p "$FX" && git -C "$FX" init -q -b main)
  git -C "$FX" config user.email t@t.t
  git -C "$FX" config user.name t
  echo '{"$schema":"x"}' > "$FX/.changeset/config.json"
}

teardown() { rm -rf "$TMPDIR"; }

monorepo() {
  echo '{"name":"root","private":true,"workspaces":["packages/*"]}' > "$FX/package.json"
  for p in "$@"; do
    mkdir -p "$FX/packages/$p"
    echo "{\"name\":\"$p\",\"version\":\"0.1.0\"}" > "$FX/packages/$p/package.json"
  done
  git -C "$FX" add -A
  git -C "$FX" commit -qm "chore: initial commit"
}

single_pkg() {
  echo '{"name":"myapp","version":"0.1.0","private":true}' > "$FX/package.json"
  git -C "$FX" add -A
  git -C "$FX" commit -qm "chore: initial commit"
}

commit() {
  echo "$RANDOM" >> "$FX/f.txt"
  git -C "$FX" add -A
  git -C "$FX" commit -qm "$1"
}

level_of() { grep -o '": [a-z]*' "$FX/.changeset/$1-benchmark.md" | sed 's/": //'; }

@test "writes one changeset per touched package at the derived level" {
  monorepo pkg-001 pkg-002
  commit "feat(pkg-001): add thing"
  commit "fix(pkg-002): fix thing"

  run "$SCRIPT_DIR/seed-changesets.sh" "$FX"
  [ "$status" -eq 0 ]
  [ "$(level_of pkg-001)" = "minor" ]
  [ "$(level_of pkg-002)" = "patch" ]
}

# Must match FerrFlow's determine_bump, or the two tools plan different releases
# and the comparison is meaningless again.
@test "breaking beats feat beats fix for the same package" {
  monorepo pkg-001 pkg-002
  commit "fix(pkg-001): a"
  commit "feat(pkg-001): b"
  commit "fix(pkg-002): c"
  commit "feat(pkg-002): d"
  commit "chore(pkg-002)!: e"

  run "$SCRIPT_DIR/seed-changesets.sh" "$FX"
  [ "$status" -eq 0 ]
  [ "$(level_of pkg-001)" = "minor" ]
  [ "$(level_of pkg-002)" = "major" ]
}

@test "perf and refactor bump patch, chore docs ci test do not" {
  monorepo pkg-001 pkg-002 pkg-003
  commit "perf(pkg-001): a"
  commit "refactor(pkg-002): b"
  commit "chore(pkg-003): c"
  commit "docs(pkg-003): d"
  commit "ci(pkg-003): e"
  commit "test(pkg-003): f"

  run "$SCRIPT_DIR/seed-changesets.sh" "$FX"
  [ "$status" -eq 0 ]
  [ "$(level_of pkg-001)" = "patch" ]
  [ "$(level_of pkg-002)" = "patch" ]
  [ ! -f "$FX/.changeset/pkg-003-benchmark.md" ]
}

# The single-package fixture scopes by area (core, api, cli), not by package —
# naming a package changesets can't resolve is a hard error.
@test "single-package fixture targets the root package, not the commit scope" {
  single_pkg
  commit "feat(core): add thing"
  commit "fix(api): fix thing"

  run "$SCRIPT_DIR/seed-changesets.sh" "$FX"
  [ "$status" -eq 0 ]
  [ "$(level_of myapp)" = "minor" ]
  [ ! -f "$FX/.changeset/core-benchmark.md" ]
}

@test "ignores scopes that are not workspace packages" {
  monorepo pkg-001
  commit "feat(pkg-001): a"
  commit "feat(not-a-package): b"

  run "$SCRIPT_DIR/seed-changesets.sh" "$FX"
  [ "$status" -eq 0 ]
  [ "$(ls "$FX/.changeset"/*-benchmark.md | wc -l)" -eq 1 ]
  [ ! -f "$FX/.changeset/not-a-package-benchmark.md" ]
}

# `single` ships a hand-written changeset on purpose; don't fight it.
@test "no-op when the fixture already ships a changeset" {
  monorepo pkg-001
  commit "feat(pkg-001): a"
  echo '---' > "$FX/.changeset/handwritten.md"

  run "$SCRIPT_DIR/seed-changesets.sh" "$FX"
  [ "$status" -eq 0 ]
  [ ! -f "$FX/.changeset/pkg-001-benchmark.md" ]
}

@test "no-op when the fixture has no changesets config" {
  monorepo pkg-001
  commit "feat(pkg-001): a"
  rm "$FX/.changeset/config.json"

  run "$SCRIPT_DIR/seed-changesets.sh" "$FX"
  [ "$status" -eq 0 ]
  [ ! -f "$FX/.changeset/pkg-001-benchmark.md" ]
}

@test "commits before the release tag are out of range" {
  monorepo pkg-001
  run "$SCRIPT_DIR/seed-changesets.sh" "$FX"
  [ "$status" -eq 0 ]
  [ ! -f "$FX/.changeset/pkg-001-benchmark.md" ]
}

@test "fails on a directory that is not a git repo" {
  run "$SCRIPT_DIR/seed-changesets.sh" "$TMPDIR/nope"
  [ "$status" -eq 2 ]
}
