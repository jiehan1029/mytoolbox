#!/bin/bash
# group_sync.sh — T4: Create/update GitNexus group and sync contracts
#
# Usage: group_sync.sh --group NAME --release-repo PATH [--cross-repo PATH] ...
#
# Note: Base repo intentionally NOT added to group (only for diff)
#
# Output:
#   STATUS:group_synced:cross_links=N
#   STATUS:gitnexus_not_installed
#   WARN:group_sync_failed:reason

set -euo pipefail

GROUP_NAME=""
RELEASE_REPO=""
CROSS_REPOS=()

while [[ $# -gt 0 ]]; do
  case $1 in
    --group) GROUP_NAME="$2"; shift 2 ;;
    --release-repo) RELEASE_REPO="$2"; shift 2 ;;
    --cross-repo) CROSS_REPOS+=("$2"); shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Check gitnexus installed
if ! command -v gitnexus &>/dev/null; then
  echo "STATUS:gitnexus_not_installed"
  exit 0
fi

# Resolve registry name for a repo path via `gitnexus list`.
# Default: basename. Falls back to basename if `gitnexus list` parsing fails.
resolve_registry_name() {
  local repo_path="$1"
  local default_name
  default_name=$(basename "$repo_path")
  # Best-effort: scan `gitnexus list` for a row mentioning this path; print 1st col.
  local matched
  matched=$(gitnexus list 2>/dev/null | awk -v p="$repo_path" '$0 ~ p {print $1; exit}')
  echo "${matched:-$default_name}"
}

# Create group if not exists
if ! gitnexus group list "$GROUP_NAME" &>/dev/null 2>&1; then
  echo "Creating group $GROUP_NAME"
  gitnexus group create "$GROUP_NAME"
fi

# Add release repo (main repo being released)
# Official: gitnexus group add <group> <groupPath> <registryName>
# Pattern: groupPath = repo filesystem path, registryName = alias from `gitnexus list`
RELEASE_REG=$(resolve_registry_name "$RELEASE_REPO")
gitnexus group add "$GROUP_NAME" "$RELEASE_REPO" "$RELEASE_REG" 2>/dev/null || true
echo "Added release repo: groupPath=$RELEASE_REPO registryName=$RELEASE_REG"

# Add cross-repos (consumers)
for cross in "${CROSS_REPOS[@]}"; do
  CROSS_REG=$(resolve_registry_name "$cross")
  gitnexus group add "$GROUP_NAME" "$cross" "$CROSS_REG" 2>/dev/null || true
  echo "Added cross-repo: groupPath=$cross registryName=$CROSS_REG"
done

# NOTE: Base repo intentionally NOT added to group
# Base is only used for diff computation, not for impact analysis

# Sync contracts
echo "Syncing contracts..."
if ! gitnexus group sync "$GROUP_NAME" 2>&1; then
  echo "WARN:group_sync_failed:sync_command_error"
  # Don't exit — partial sync may still be useful
fi

# Get cross-link count from `gitnexus group contracts` (text output — no --json flag in official cli)
CONTRACTS_OUT=$(gitnexus group contracts "$GROUP_NAME" 2>/dev/null || true)
CROSS_LINKS=$(echo "$CONTRACTS_OUT" | grep -iE "cross[-_ ]?links?" | grep -oE '[0-9]+' | head -1)
CROSS_LINKS="${CROSS_LINKS:-0}"

# Check per-repo staleness — surface stale consumers as warnings
STALE=$(gitnexus group status "$GROUP_NAME" 2>/dev/null | grep -i "stale\|outdated" || true)
if [[ -n "$STALE" ]]; then
  echo "WARN:group_stale_repos:$(echo "$STALE" | tr '\n' ',' | sed 's/,$//')"
fi

echo "STATUS:group_synced:cross_links=$CROSS_LINKS"
