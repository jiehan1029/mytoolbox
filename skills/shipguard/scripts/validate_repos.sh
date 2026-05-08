#!/bin/bash
# validate_repos.sh — Pre-confirmation validation
# Run BEFORE user confirms to surface problems early
#
# Usage: validate_repos.sh --release-repo PATH --release-branch BRANCH \
#                          --base-branch BRANCH \
#                          [--cross-repo PATH[@BRANCH]] ...
#
# Exit codes:
#   0 - All validations passed
#   1 - Fatal error (missing release repo)
#   2 - Warnings only (can proceed with user acknowledgment)
#
# Output format (JSON-like for easy parsing):
#   VALID:release_repo:/path
#   VALID:base_branch:main
#   WARN:cross_repo:/path:cannot_fetch_remote:sha=abc123
#   ERROR:cross_repo:/path:not_found
#   ERROR:cross_branch:feature/x:not_found_in:/path

set -euo pipefail

RELEASE_REPO=""
RELEASE_BRANCH=""
BASE_BRANCH=""
CROSS_REPOS=()
WARNINGS=0
ERRORS=0

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --release-repo) RELEASE_REPO="$2"; shift 2 ;;
    --release-branch) RELEASE_BRANCH="$2"; shift 2 ;;
    --base-branch) BASE_BRANCH="$2"; shift 2 ;;
    --cross-repo) CROSS_REPOS+=("$2"); shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Validate release repo exists
if [[ ! -d "$RELEASE_REPO/.git" ]]; then
  echo "ERROR:release_repo:$RELEASE_REPO:not_a_git_repo"
  exit 1
fi
echo "VALID:release_repo:$RELEASE_REPO"

# Validate release branch exists locally or can be fetched
if ! git -C "$RELEASE_REPO" rev-parse --verify "$RELEASE_BRANCH" &>/dev/null; then
  # Try to fetch it
  if git -C "$RELEASE_REPO" fetch origin "$RELEASE_BRANCH" &>/dev/null; then
    echo "VALID:release_branch:$RELEASE_BRANCH:fetched_from_remote"
  else
    echo "ERROR:release_branch:$RELEASE_BRANCH:not_found_locally_or_remote"
    ERRORS=$((ERRORS + 1))
  fi
else
  echo "VALID:release_branch:$RELEASE_BRANCH:exists_locally"
fi

# Validate base branch exists locally or can be fetched
if ! git -C "$RELEASE_REPO" rev-parse --verify "$BASE_BRANCH" &>/dev/null; then
  # Try to fetch it
  if git -C "$RELEASE_REPO" fetch origin "$BASE_BRANCH" &>/dev/null; then
    echo "VALID:base_branch:$BASE_BRANCH:fetched_from_remote"
  else
    echo "ERROR:base_branch:$BASE_BRANCH:not_found_locally_or_remote"
    ERRORS=$((ERRORS + 1))
  fi
else
  echo "VALID:base_branch:$BASE_BRANCH:exists_locally"
fi

# Validate each cross-repo
for entry in "${CROSS_REPOS[@]}"; do
  # Parse path@branch format
  if [[ "$entry" == *"@"* ]]; then
    CROSS_PATH="${entry%@*}"
    CROSS_BRANCH="${entry#*@}"
  else
    CROSS_PATH="$entry"
    CROSS_BRANCH="$BASE_BRANCH"
  fi

  # Check if repo exists locally
  if [[ ! -d "$CROSS_PATH/.git" ]]; then
    echo "ERROR:cross_repo:$CROSS_PATH:not_found"
    ERRORS=$((ERRORS + 1))
    continue
  fi

  # Check if branch exists locally
  if ! git -C "$CROSS_PATH" rev-parse --verify "$CROSS_BRANCH" &>/dev/null; then
    # Try to fetch it
    if git -C "$CROSS_PATH" fetch origin "$CROSS_BRANCH" &>/dev/null; then
      echo "VALID:cross_repo:$CROSS_PATH@$CROSS_BRANCH:fetched_from_remote"
    else
      echo "ERROR:cross_branch:$CROSS_BRANCH:not_found_in:$CROSS_PATH"
      ERRORS=$((ERRORS + 1))
      continue
    fi
  fi

  # Try to fetch latest (warn if fails but continue)
  CURRENT_SHA=$(git -C "$CROSS_PATH" rev-parse HEAD 2>/dev/null || echo "unknown")
  if ! git -C "$CROSS_PATH" fetch origin "$CROSS_BRANCH" &>/dev/null; then
    echo "WARN:cross_repo:$CROSS_PATH@$CROSS_BRANCH:cannot_fetch_remote:sha=$CURRENT_SHA"
    WARNINGS=$((WARNINGS + 1))
  else
    echo "VALID:cross_repo:$CROSS_PATH@$CROSS_BRANCH:remote_accessible"
  fi
done

# Summary
echo "---"
echo "SUMMARY:errors=$ERRORS:warnings=$WARNINGS"

if [[ $ERRORS -gt 0 ]]; then
  exit 1
elif [[ $WARNINGS -gt 0 ]]; then
  exit 2
else
  exit 0
fi
