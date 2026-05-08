#!/bin/bash
# provision_cross.sh — compatibility wrapper
# Canonical implementation lives in provision_all.sh.

set -euo pipefail

CROSS_REPO=""
CROSS_BRANCH=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --repo) CROSS_REPO="$2"; shift 2 ;;
    --branch) CROSS_BRANCH="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/provision_all.sh" \
  --mode cross \
  --cross-repo "$CROSS_REPO@$CROSS_BRANCH"
