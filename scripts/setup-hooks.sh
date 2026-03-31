#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
HOOK_SRC="$REPO_ROOT/scripts/pre-push"
HOOK_DST="$REPO_ROOT/.git/hooks/pre-push"

echo "Installing git pre-push hook..."
cp "$HOOK_SRC" "$HOOK_DST"
chmod +x "$HOOK_DST"
echo "Done. Hook installed at .git/hooks/pre-push"
echo ""
echo "Tool check:"

command -v swiftlint &>/dev/null && echo "  swiftlint $(swiftlint version)" || echo "  swiftlint missing — brew install swiftlint"
[ -x "$REPO_ROOT/Android/gradlew" ] && echo "  Android gradlew found" || echo "  Android gradlew missing"
command -v dart &>/dev/null && echo "  dart $(dart --version 2>&1 | head -1)" || echo "  dart missing — install Flutter SDK"
command -v pnpm &>/dev/null && echo "  pnpm $(pnpm --version)" || echo "  pnpm missing — npm install -g pnpm"
