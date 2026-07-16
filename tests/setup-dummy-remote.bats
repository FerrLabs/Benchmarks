#!/usr/bin/env bats

# setup_dummy_remote lives in run.sh, which needs hyperfine and a full fixture
# tree to execute. Source just the function.
RUN_SH="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/run.sh"

setup() {
  TMPDIR="$(mktemp -d)"
  FX="$TMPDIR/fx"
  BARE="$TMPDIR/bare"
  mkdir -p "$FX" "$BARE"
  # `master` is the stock runner default and what makes the HEAD bug appear;
  # a machine with init.defaultBranch=main hides it.
  git -C "$FX" -c init.defaultBranch=main init -q
  git -C "$FX" config user.email t@t.t
  git -C "$FX" config user.name t
  echo hi > "$FX/f.txt"
  git -C "$FX" add -A
  git -C "$FX" commit -qm "chore: initial commit"
  git -C "$FX" tag v0.1.0
  git -C "$BARE" -c init.defaultBranch=master init --bare -q

  eval "$(sed -n '/^setup_dummy_remote() {/,/^}/p' "$RUN_SH")"
}

teardown() { rm -rf "$TMPDIR"; }

origin_url() { git -C "$FX" remote get-url origin; }

# semantic-release feeds origin to `new URL()`; a bare path throws
# `TypeError: Invalid URL` and the tool SKIPs the fixture entirely.
@test "origin is a file:// URL, not a bare path" {
  run setup_dummy_remote "$FX" "$BARE"
  [ "$status" -eq 0 ]
  [[ "$(origin_url)" == file://* ]]
}

# Ties the assertion to the actual consumer. Note this one only bites on
# POSIX: a Windows path parses (`C:/x` reads as protocol `c:`), so it goes
# green on a dev box even with a bare path. The test above is the portable
# guard; this one is why.
@test "the origin URL is parseable by new URL()" {
  setup_dummy_remote "$FX" "$BARE"
  run node -e "new URL(process.argv[1]); console.log('ok')" "$(origin_url)"
  [ "$status" -eq 0 ]
  [ "$output" = "ok" ]
}

# `git init --bare` points HEAD at init.defaultBranch (master on a stock
# runner) while fixtures are on main, so `git fetch` dies on a dangling HEAD.
@test "the remote's HEAD points at the branch we pushed" {
  setup_dummy_remote "$FX" "$BARE"
  [ "$(git -C "$BARE" symbolic-ref HEAD)" = "refs/heads/main" ]
}

@test "git can fetch from the remote we built" {
  setup_dummy_remote "$FX" "$BARE"
  run git -C "$FX" fetch --tags "$(origin_url)"
  [ "$status" -eq 0 ]
}

@test "commits and tags actually land on the remote" {
  setup_dummy_remote "$FX" "$BARE"
  run git -C "$BARE" for-each-ref --format='%(refname)'
  [[ "$output" == *"refs/heads/main"* ]]
  [[ "$output" == *"refs/tags/v0.1.0"* ]]
}

@test "a detached HEAD fails loudly instead of building a broken remote" {
  git -C "$FX" checkout -q --detach HEAD
  run setup_dummy_remote "$FX" "$BARE"
  [ "$status" -ne 0 ]
  [[ "$output" == *"detached HEAD"* ]]
}

@test "re-running against an existing origin is not fatal" {
  setup_dummy_remote "$FX" "$BARE"
  run setup_dummy_remote "$FX" "$BARE"
  [ "$status" -eq 0 ]
  [[ "$(origin_url)" == file://* ]]
}
