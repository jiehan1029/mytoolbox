#!/bin/bash
# provision_release.sh — T1: Fetch + index release repo
#
# Usage: provision_release.sh --repo PATH --branch BRANCH
#
# Output:
#   STATUS:indexed_fresh
#   STATUS:indexed_new
#   STATUS:gitnexus_not_installed
#   ERROR:...

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

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/release-gatekeeper"
CACHE_FILE="$CACHE_DIR/sha-$(echo -n "$REPO_PATH" | md5sum | cut -d' ' -f1)"
mkdir -p "$CACHE_DIR"

# 1. Fetch latest from remote
echo "Fetching origin/$RELEASE_BRANCH..."
git -C "$REPO_PATH" fetch origin "$RELEASE_BRANCH" || true

# 2. Check if local is behind remote
LOCAL=$(git -C "$REPO_PATH" rev-parse "$RELEASE_BRANCH" 2>/dev/null || echo "")
REMOTE=$(git -C "$REPO_PATH" rev-parse "origin/$RELEASE_BRANCH" 2>/dev/null || echo "")

if [[ -n "$REMOTE" && "$LOCAL" != "$REMOTE" ]]; then
  echo "Pulling latest changes for $RELEASE_BRANCH"
  git -C "$REPO_PATH" checkout "$RELEASE_BRANCH"
  git -C "$REPO_PATH" pull origin "$RELEASE_BRANCH"
fi

# 3. Check GitNexus installation
if ! command -v gitnexus &>/dev/null; then
  echo "STATUS:gitnexus_not_installed"
  exit 0
fi

# 4. Check if index fresh via cache
CACHED_SHA=$(cat "$CACHE_FILE" 2>/dev/null || echo "")
HEAD_SHA=$(git -C "$REPO_PATH" rev-parse HEAD)
IN_REGISTRY=$(gitnexus list 2>/dev/null | grep -qF "$REPO_PATH" && echo "yes" || echo "no")

if [[ "$CACHED_SHA" = "$HEAD_SHA" && "$IN_REGISTRY" = "yes" ]]; then
  echo "STATUS:indexed_fresh:sha=$HEAD_SHA"
else
  echo "Indexing $REPO_PATH (cached: ${CACHED_SHA:-none}, now: $HEAD_SHA)"
  gitnexus analyze "$REPO_PATH" --skip-agents-md --skip-embeddings
  echo "$HEAD_SHA" > "$CACHE_FILE"
  echo "STATUS:indexed_new:sha=$HEAD_SHA"
fi
