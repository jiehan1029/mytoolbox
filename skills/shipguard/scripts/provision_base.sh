#!/bin/bash
# provision_base.sh — compatibility wrapper
# Canonical implementation lives in provision_all.sh.

set -euo pipefail

RELEASE_REPO=""
BASE_REPO=""
BASE_BRANCH=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --release-repo) RELEASE_REPO="$2"; shift 2 ;;
    --base-repo) BASE_REPO="$2"; shift 2 ;;
    --branch) BASE_BRANCH="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/provision_all.sh" \
  --mode base \
  --release-repo "$RELEASE_REPO" \
  --base-repo "$BASE_REPO" \
  --base-branch "$BASE_BRANCH"
