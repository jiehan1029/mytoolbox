#!/bin/bash
# install_permissions.sh — Merge shipguard's recommended permissions into Claude Code settings.
#
# Usage:
#   bash install_permissions.sh                  # Merge into ~/.claude/settings.json (user-global)
#   bash install_permissions.sh --project        # Merge into <cwd>/.claude/settings.local.json (project-local)
#   bash install_permissions.sh --check          # Print which perms are missing (no write)
#
# Idempotent: only adds missing entries. Always creates a .bak backup before writing.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PERMS_SRC="$SCRIPT_DIR/../permissions.json"

if ! command -v jq &>/dev/null; then
  echo "ERROR: jq required. Install via 'brew install jq' (macOS) or your package manager."
  exit 1
fi

if [[ ! -f "$PERMS_SRC" ]]; then
  echo "ERROR: $PERMS_SRC not found"
  exit 1
fi

MODE="user"
CHECK_ONLY=false
while [[ $# -gt 0 ]]; do
  case $1 in
    --project) MODE="project"; shift ;;
    --check) CHECK_ONLY=true; shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [[ "$MODE" = "user" ]]; then
  TARGET="$HOME/.claude/settings.json"
else
  mkdir -p "$(pwd)/.claude"
  TARGET="$(pwd)/.claude/settings.local.json"
fi

# Ensure target exists with valid JSON
if [[ ! -f "$TARGET" ]]; then
  echo '{}' > "$TARGET"
fi
if ! jq empty "$TARGET" 2>/dev/null; then
  echo "ERROR: $TARGET is not valid JSON. Fix or back up before running."
  exit 1
fi

# Compute missing perms
NEEDED=$(jq -r '.permissions.allow[]' "$PERMS_SRC")
EXISTING=$(jq -r '.permissions.allow[]?' "$TARGET" 2>/dev/null || true)
MISSING=$(comm -23 <(echo "$NEEDED" | sort -u) <(echo "$EXISTING" | sort -u))

if [[ -z "$MISSING" ]]; then
  echo "OK: all shipguard permissions already present in $TARGET"
  exit 0
fi

echo "Target: $TARGET"
echo "Missing entries:"
echo "$MISSING" | sed 's/^/  - /'

if $CHECK_ONLY; then
  exit 0
fi

# Backup
cp "$TARGET" "$TARGET.bak.$(date +%Y%m%d-%H%M%S)"

# Merge: union existing + needed (preserves non-permissions keys, dedupes allow array)
TMP=$(mktemp)
jq --slurpfile src "$PERMS_SRC" '
  .permissions = (.permissions // {}) |
  .permissions.allow = ((.permissions.allow // []) + $src[0].permissions.allow | unique)
' "$TARGET" > "$TMP" && mv "$TMP" "$TARGET"

echo "Merged. Backup: $TARGET.bak.*"
