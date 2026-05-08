#!/bin/bash
# provision_release.sh — compatibility wrapper
# Canonical implementation lives in provision_all.sh.

set -euo pipefail

REPO_PATH=""
RELEASE_BRANCH=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --repo) REPO_PATH="$2"; shift 2 ;;
    --branch) RELEASE_BRANCH="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/provision_all.sh" \
  --mode release \
  --release-repo "$REPO_PATH" \
  --release-branch "$RELEASE_BRANCH"
