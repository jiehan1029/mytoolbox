#!/bin/bash
# provision_base.sh — T2: Clone/fetch + index base repo (separate folder)
#
# Usage: provision_base.sh --release-repo PATH --base-repo PATH --branch BRANCH
#
# Output:
#   STATUS:base_ready:sha=...
#   STATUS:base_ready_no_index (gitnexus not installed)
#   ERROR:remote_mismatch:...

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

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/release-gatekeeper"
CACHE_FILE="$CACHE_DIR/sha-$(echo -n "$BASE_REPO" | md5sum | cut -d' ' -f1)"
mkdir -p "$CACHE_DIR"

# 1. Get release repo remote URL
REMOTE_URL=$(git -C "$RELEASE_REPO" remote get-url origin)

# 2. Create or validate base repo folder
if [[ ! -d "$BASE_REPO/.git" ]]; then
  echo "Cloning base repo to $BASE_REPO"
  git clone "$REMOTE_URL" "$BASE_REPO"
else
  # Validate same remote
  BASE_REMOTE=$(git -C "$BASE_REPO" remote get-url origin)
  if [[ "$BASE_REMOTE" != "$REMOTE_URL" ]]; then
    echo "ERROR:remote_mismatch:expected=$REMOTE_URL:got=$BASE_REMOTE"
    exit 1
  fi
  echo "Base repo folder exists, validating remote... OK"
fi

# 3. Fetch and checkout base branch
echo "Fetching origin/$BASE_BRANCH..."
git -C "$BASE_REPO" fetch origin "$BASE_BRANCH"
git -C "$BASE_REPO" checkout "$BASE_BRANCH"
git -C "$BASE_REPO" pull origin "$BASE_BRANCH"

HEAD_SHA=$(git -C "$BASE_REPO" rev-parse HEAD)

# 4. Index base repo (for cross-reference, not in group)
if command -v gitnexus &>/dev/null; then
  CACHED_SHA=$(cat "$CACHE_FILE" 2>/dev/null || echo "")
  IN_REGISTRY=$(gitnexus list 2>/dev/null | grep -qF "$BASE_REPO" && echo "yes" || echo "no")

  if [[ "$CACHED_SHA" = "$HEAD_SHA" && "$IN_REGISTRY" = "yes" ]]; then
    echo "Base repo index fresh"
  else
    echo "Indexing base repo..."
    gitnexus analyze "$BASE_REPO" --skip-agents-md --skip-embeddings
    echo "$HEAD_SHA" > "$CACHE_FILE"
  fi
  echo "STATUS:base_ready:sha=$HEAD_SHA"
else
  echo "STATUS:base_ready_no_index:sha=$HEAD_SHA"
fi
