#!/usr/bin/env bash
set -euo pipefail

# Give `changesets status` the same release to plan as every other tool.
#
# Usage: ./seed-changesets.sh <fixture-dir>
#
# changesets does not read git history — it plans from `.changeset/*.md` files a
# human writes by hand. Benchmarking it against a fixture with none measures
# `npx` plus Node boot and nothing else: its time tracks package count, stays
# flat across a 100x range of commits, and "wins" the big fixtures against tools
# that actually walked them. That flatters us on the small fixtures and
# penalises us on the large ones, and neither number means anything.
#
# So write the changesets a maintainer would have written for this history: one
# per package with a releasable commit since the release tag, at the level
# FerrFlow derives from the same commits (breaking > feat > fix/perf/refactor,
# per FerrFlow's src/conventional_commits.rs). Both tools then plan the same
# release from equivalent input.
#
# No-op when the fixture ships changesets by hand, or has no changesets config.
#
# Requires: git, jq, awk

FIXTURE_DIR="${1:-}"

if [[ -z "$FIXTURE_DIR" ]]; then
  echo "Usage: $0 <fixture-dir>" >&2
  exit 2
fi
if [[ ! -d "$FIXTURE_DIR/.git" ]]; then
  echo "Not a git fixture: $FIXTURE_DIR" >&2
  exit 2
fi
if [[ ! -f "$FIXTURE_DIR/.changeset/config.json" ]]; then
  exit 0
fi
if compgen -G "$FIXTURE_DIR/.changeset/*.md" > /dev/null; then
  exit 0
fi

root_pkg="$FIXTURE_DIR/package.json"
[[ -f "$root_pkg" ]] || exit 0

# A changeset naming a package changesets can't resolve is a hard error, so the
# package set comes from the workspace rather than from the commit scopes. The
# single-package fixture scopes its commits by area (core, api, cli...), not by
# package name, so scopes are only trustworthy in the monorepo layout.
SINGLE=""
PKG_LIST=""
if jq -e '.workspaces' "$root_pkg" >/dev/null 2>&1; then
  while IFS= read -r p; do
    name=$(jq -r '.name // empty' "$p" 2>/dev/null || true)
    [[ -n "$name" ]] && PKG_LIST="$PKG_LIST $name"
  done < <(find "$FIXTURE_DIR/packages" -mindepth 2 -maxdepth 2 -name package.json 2>/dev/null | sort)
  [[ -n "$PKG_LIST" ]] || exit 0
else
  SINGLE=$(jq -r '.name // empty' "$root_pkg")
  [[ -n "$SINGLE" ]] || exit 0
fi

# Every package's v0.1.0 is tagged at the root commit, so "since the last
# release" and "since the root commit" are the same range here — and reading it
# from the graph avoids guessing tag names, which differ between the single
# (`v0.1.0`) and monorepo (`pkg-001@v0.1.0`) layouts.
base=$(git -C "$FIXTURE_DIR" rev-list --max-parents=0 HEAD | tail -1)

# One awk pass, not a shell read loop: mono-large is 10k commits and the
# bash-regex version takes minutes.
mapfile -t PAIRS < <(
  git -C "$FIXTURE_DIR" log "$base..HEAD" --format='%s' |
    awk -v single="$SINGLE" -v pkgs="$PKG_LIST" '
      BEGIN {
        n = split(pkgs, a, " ")
        for (i = 1; i <= n; i++) known[a[i]] = 1
        rank["patch"] = 1; rank["minor"] = 2; rank["major"] = 3
      }
      {
        if (match($0, /^[a-z]+(\([^)]*\))?!?:/) == 0) next
        head = substr($0, 1, RLENGTH)
        bang = (head ~ /!:$/)

        type = head
        sub(/[(!:].*$/, "", type)

        scope = ""
        if (head ~ /\(/) {
          scope = head
          sub(/^[a-z]+\(/, "", scope)
          sub(/\).*$/, "", scope)
        }

        if (bang) level = "major"
        else if (type == "feat") level = "minor"
        else if (type == "fix" || type == "perf" || type == "refactor") level = "patch"
        else next

        if (single != "") target = single
        else if (scope != "" && (scope in known)) target = scope
        else next

        if (rank[level] > rank[best[target]]) best[target] = level
      }
      END { for (t in best) printf "%s %s\n", t, best[t] }
    ' | sort
)

count=0
for pair in "${PAIRS[@]}"; do
  [[ -n "$pair" ]] || continue
  pkg="${pair%% *}"
  level="${pair##* }"
  file="$FIXTURE_DIR/.changeset/${pkg//\//-}-benchmark.md"
  {
    printf -- '---\n'
    printf -- '"%s": %s\n' "$pkg" "$level"
    printf -- '---\n\n'
    printf -- 'Release %s at %s, derived from the conventional commits since the last tag.\n' \
      "$pkg" "$level"
  } > "$file"
  count=$((count + 1))
done

echo "Seeded $count changeset(s) in $FIXTURE_DIR/.changeset" >&2
