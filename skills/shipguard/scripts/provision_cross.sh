#!/bin/bash
# provision_cross.sh — T3: Fetch + index a single cross-repo
#
# Usage: provision_cross.sh --repo PATH --branch BRANCH
#
# Output:
#   STATUS:cross_ready:PATH:sha=...
#   STATUS:cross_ready_no_index:PATH:sha=...
#   WARN:cross_repo:PATH:fetch_failed:sha=... (proceeds with local)
#   ERROR:repo_not_found:PATH

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

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/release-gatekeeper"
CACHE_FILE="$CACHE_DIR/sha-$(echo -n "$CROSS_REPO" | md5sum | cut -d' ' -f1)"
mkdir -p "$CACHE_DIR"

# 1. Verify repo exists
if [[ ! -d "$CROSS_REPO/.git" ]]; then
  echo "ERROR:repo_not_found:$CROSS_REPO"
  exit 1
fi

# 2. Try to fetch + checkout (warn if fetch fails)
FETCH_OK=true
if ! git -C "$CROSS_REPO" fetch origin "$CROSS_BRANCH" 2>/dev/null; then
  FETCH_OK=false
  CURRENT_SHA=$(git -C "$CROSS_REPO" rev-parse HEAD 2>/dev/null || echo "unknown")
  echo "WARN:cross_repo:$CROSS_REPO:fetch_failed:sha=$CURRENT_SHA"
fi

# Checkout branch if it exists
if git -C "$CROSS_REPO" rev-parse --verify "$CROSS_BRANCH" &>/dev/null; then
  git -C "$CROSS_REPO" checkout "$CROSS_BRANCH"
  if [[ "$FETCH_OK" = true ]]; then
    git -C "$CROSS_REPO" pull origin "$CROSS_BRANCH" 2>/dev/null || true
  fi
elif git -C "$CROSS_REPO" rev-parse --verify "origin/$CROSS_BRANCH" &>/dev/null; then
  git -C "$CROSS_REPO" checkout -b "$CROSS_BRANCH" "origin/$CROSS_BRANCH"
else
  echo "ERROR:branch_not_found:$CROSS_BRANCH:in:$CROSS_REPO"
  exit 1
fi

HEAD_SHA=$(git -C "$CROSS_REPO" rev-parse HEAD)

# 3. Index if gitnexus available
if command -v gitnexus &>/dev/null; then
  CACHED_SHA=$(cat "$CACHE_FILE" 2>/dev/null || echo "")
  IN_REGISTRY=$(gitnexus list 2>/dev/null | grep -qF "$CROSS_REPO" && echo "yes" || echo "no")

  if [[ "$CACHED_SHA" = "$HEAD_SHA" && "$IN_REGISTRY" = "yes" ]]; then
    echo "Cross-repo $CROSS_REPO index fresh"
  else
    echo "Indexing $CROSS_REPO..."
    gitnexus analyze "$CROSS_REPO" --skip-agents-md --skip-embeddings
    echo "$HEAD_SHA" > "$CACHE_FILE"
  fi
  echo "STATUS:cross_ready:$CROSS_REPO:sha=$HEAD_SHA"
else
  echo "STATUS:cross_ready_no_index:$CROSS_REPO:sha=$HEAD_SHA"
fi
