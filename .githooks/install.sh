#!/usr/bin/env bash
set -euo pipefail
git config core.hooksPath .githooks
chmod +x .githooks/pre-push 2>/dev/null || true
echo "Git hooks installed (core.hooksPath=.githooks)."
echo "pre-push: shellcheck scripts/*.sh + bats tests/ (skipped if tools missing)"
