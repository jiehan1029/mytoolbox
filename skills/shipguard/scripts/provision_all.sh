#!/bin/bash
# provision_all.sh — unified validation + provisioning entrypoint
#
# Modes:
#   --mode validate  -> validate repos/branches only
#   --mode release   -> provision release repo only
#   --mode base      -> provision base repo only
#   --mode cross     -> provision one cross-repo only
#   --mode all       -> validate, confirm-ready provisioning, joinpoint output
#
# Notes:
# - This script is the canonical implementation for Phase 1.
# - Legacy scripts delegate to this script to preserve compatibility.

set -euo pipefail

MODE="all"
RELEASE_REPO=""
RELEASE_BRANCH=""
BASE_REPO=""
BASE_BRANCH=""
GROUP_NAME=""
CROSS_REPOS=()

WARNINGS=0
ERRORS=0
VALID_CROSS_REPOS=()
GITNEXUS_AVAILABLE=false

if command -v gitnexus &>/dev/null; then
  GITNEXUS_AVAILABLE=true
fi

hash_string() {
  local value="$1"
  if command -v shasum &>/dev/null; then
    printf '%s' "$value" | shasum -a 256 | awk '{print $1}'
  elif command -v md5sum &>/dev/null; then
    printf '%s' "$value" | md5sum | awk '{print $1}'
  elif command -v md5 &>/dev/null; then
    md5 -q -s "$value"
  else
    printf '%s' "$value" | tr '/ ' '__'
  fi
}

cache_file_for_path() {
  local repo_path="$1"
  local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/release-gatekeeper"
  mkdir -p "$cache_dir"
  local key
  key=$(hash_string "$repo_path")
  printf '%s/sha-%s' "$cache_dir" "$key"
}

parse_cross_entry() {
  local entry="$1"
  local default_branch="$2"
  if [[ "$entry" == *"@"* ]]; then
    printf '%s|%s' "${entry%@*}" "${entry#*@}"
  else
    printf '%s|%s' "$entry" "$default_branch"
  fi
}

validate_branch() {
  local repo_path="$1"
  local branch="$2"
  local label="$3"

  if git -C "$repo_path" rev-parse --verify "$branch" &>/dev/null; then
    echo "VALID:${label}:${branch}:exists_locally"
    return 0
  fi

  if git -C "$repo_path" fetch origin "$branch" &>/dev/null; then
    echo "VALID:${label}:${branch}:fetched_from_remote"
    return 0
  fi

  echo "ERROR:${label}:${branch}:not_found_locally_or_remote"
  ERRORS=$((ERRORS + 1))
  return 1
}

run_validate() {
  WARNINGS=0
  ERRORS=0
  VALID_CROSS_REPOS=()

  if [[ ! -d "$RELEASE_REPO/.git" ]]; then
    echo "ERROR:release_repo:$RELEASE_REPO:not_a_git_repo"
    exit 1
  fi
  echo "VALID:release_repo:$RELEASE_REPO"

  validate_branch "$RELEASE_REPO" "$RELEASE_BRANCH" "release_branch" || true
  validate_branch "$RELEASE_REPO" "$BASE_BRANCH" "base_branch" || true

  for entry in "${CROSS_REPOS[@]}"; do
    local parsed cross_path cross_branch
    parsed=$(parse_cross_entry "$entry" "$BASE_BRANCH")
    cross_path="${parsed%%|*}"
    cross_branch="${parsed##*|}"

    if [[ ! -d "$cross_path/.git" ]]; then
      echo "ERROR:cross_repo:$cross_path:not_found"
      ERRORS=$((ERRORS + 1))
      continue
    fi

    if ! git -C "$cross_path" rev-parse --verify "$cross_branch" &>/dev/null; then
      if git -C "$cross_path" fetch origin "$cross_branch" &>/dev/null; then
        echo "VALID:cross_repo:$cross_path@$cross_branch:fetched_from_remote"
      else
        echo "ERROR:cross_branch:$cross_branch:not_found_in:$cross_path"
        ERRORS=$((ERRORS + 1))
        continue
      fi
    fi

    local current_sha
    current_sha=$(git -C "$cross_path" rev-parse HEAD 2>/dev/null || echo "unknown")
    if ! git -C "$cross_path" fetch origin "$cross_branch" &>/dev/null; then
      echo "WARN:cross_repo:$cross_path@$cross_branch:cannot_fetch_remote:sha=$current_sha"
      WARNINGS=$((WARNINGS + 1))
    else
      echo "VALID:cross_repo:$cross_path@$cross_branch:remote_accessible"
    fi

    VALID_CROSS_REPOS+=("$cross_path@$cross_branch")
  done

  echo "---"
  echo "SUMMARY:errors=$ERRORS:warnings=$WARNINGS"

  if [[ $ERRORS -gt 0 ]]; then
    return 1
  elif [[ $WARNINGS -gt 0 ]]; then
    return 2
  fi
  return 0
}

index_repo_if_needed() {
  local repo_path="$1"
  local head_sha="$2"

  if [[ "$GITNEXUS_AVAILABLE" != true ]]; then
    echo "no_index"
    return 0
  fi

  local cache_file cached_sha in_registry
  cache_file=$(cache_file_for_path "$repo_path")
  cached_sha=$(cat "$cache_file" 2>/dev/null || echo "")
  in_registry="no"
  if gitnexus list 2>/dev/null | grep -qF "$repo_path"; then
    in_registry="yes"
  fi

  if [[ "$cached_sha" = "$head_sha" && "$in_registry" = "yes" ]]; then
    echo "fresh"
    return 0
  fi

  gitnexus analyze "$repo_path" --skip-agents-md --skip-embeddings
  echo "$head_sha" > "$cache_file"
  echo "new"
}

run_release() {
  echo "Fetching origin/$RELEASE_BRANCH..."
  git -C "$RELEASE_REPO" fetch origin "$RELEASE_BRANCH" || true

  local local_sha remote_sha
  local_sha=$(git -C "$RELEASE_REPO" rev-parse "$RELEASE_BRANCH" 2>/dev/null || echo "")
  remote_sha=$(git -C "$RELEASE_REPO" rev-parse "origin/$RELEASE_BRANCH" 2>/dev/null || echo "")

  if [[ -n "$remote_sha" && "$local_sha" != "$remote_sha" ]]; then
    echo "Pulling latest changes for $RELEASE_BRANCH"
    git -C "$RELEASE_REPO" checkout "$RELEASE_BRANCH"
    git -C "$RELEASE_REPO" pull origin "$RELEASE_BRANCH"
  fi

  local head_sha
  head_sha=$(git -C "$RELEASE_REPO" rev-parse HEAD)

  if [[ "$GITNEXUS_AVAILABLE" != true ]]; then
    echo "STATUS:gitnexus_not_installed"
    echo "STATUS:release_ready:sha=$head_sha"
    return 0
  fi

  local idx
  idx=$(index_repo_if_needed "$RELEASE_REPO" "$head_sha")
  if [[ "$idx" = "fresh" ]]; then
    echo "STATUS:indexed_fresh:sha=$head_sha"
  else
    echo "STATUS:indexed_new:sha=$head_sha"
  fi
  echo "STATUS:release_ready:sha=$head_sha"
}

run_base() {
  local remote_url
  remote_url=$(git -C "$RELEASE_REPO" remote get-url origin)

  if [[ ! -d "$BASE_REPO/.git" ]]; then
    echo "Cloning base repo to $BASE_REPO"
    git clone "$remote_url" "$BASE_REPO"
  else
    local base_remote
    base_remote=$(git -C "$BASE_REPO" remote get-url origin)
    if [[ "$base_remote" != "$remote_url" ]]; then
      echo "ERROR:remote_mismatch:expected=$remote_url:got=$base_remote"
      return 1
    fi
    echo "Base repo folder exists, validating remote... OK"
  fi

  echo "Fetching origin/$BASE_BRANCH..."
  git -C "$BASE_REPO" fetch origin "$BASE_BRANCH"
  git -C "$BASE_REPO" checkout "$BASE_BRANCH"
  git -C "$BASE_REPO" pull origin "$BASE_BRANCH"

  local head_sha
  head_sha=$(git -C "$BASE_REPO" rev-parse HEAD)

  if [[ "$GITNEXUS_AVAILABLE" = true ]]; then
    index_repo_if_needed "$BASE_REPO" "$head_sha" >/dev/null
    echo "STATUS:base_ready:sha=$head_sha"
  else
    echo "STATUS:base_ready_no_index:sha=$head_sha"
  fi
}

run_cross() {
  local cross_path="$1"
  local cross_branch="$2"

  if [[ ! -d "$cross_path/.git" ]]; then
    echo "ERROR:repo_not_found:$cross_path"
    return 1
  fi

  local fetch_ok=true
  if ! git -C "$cross_path" fetch origin "$cross_branch" 2>/dev/null; then
    fetch_ok=false
    local current_sha
    current_sha=$(git -C "$cross_path" rev-parse HEAD 2>/dev/null || echo "unknown")
    echo "WARN:cross_repo:$cross_path:fetch_failed:sha=$current_sha"
  fi

  if git -C "$cross_path" rev-parse --verify "$cross_branch" &>/dev/null; then
    git -C "$cross_path" checkout "$cross_branch"
    if [[ "$fetch_ok" = true ]]; then
      git -C "$cross_path" pull origin "$cross_branch" 2>/dev/null || true
    fi
  elif git -C "$cross_path" rev-parse --verify "origin/$cross_branch" &>/dev/null; then
    git -C "$cross_path" checkout -B "$cross_branch" "origin/$cross_branch"
  else
    echo "ERROR:branch_not_found:$cross_branch:in:$cross_path"
    return 1
  fi

  local head_sha
  head_sha=$(git -C "$cross_path" rev-parse HEAD)

  if [[ "$GITNEXUS_AVAILABLE" = true ]]; then
    index_repo_if_needed "$cross_path" "$head_sha" >/dev/null
    echo "STATUS:cross_ready:$cross_path:sha=$head_sha"
  else
    echo "STATUS:cross_ready_no_index:$cross_path:sha=$head_sha"
  fi
}

run_group_sync() {
  local cross_paths=()
  while [[ $# -gt 0 ]]; do
    cross_paths+=("$1")
    shift
  done

  if [[ -z "$GROUP_NAME" ]]; then
    GROUP_NAME="shipguard-$(basename "$RELEASE_REPO")"
  fi

  local cmd=("$SCRIPT_DIR/group_sync.sh" "--group" "$GROUP_NAME" "--release-repo" "$RELEASE_REPO")
  local cross
  for cross in "${cross_paths[@]}"; do
    cmd+=("--cross-repo" "$cross")
  done
  bash "${cmd[@]}"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

while [[ $# -gt 0 ]]; do
  case $1 in
    --mode) MODE="$2"; shift 2 ;;
    --release-repo) RELEASE_REPO="$2"; shift 2 ;;
    --release-branch) RELEASE_BRANCH="$2"; shift 2 ;;
    --base-repo) BASE_REPO="$2"; shift 2 ;;
    --base-branch) BASE_BRANCH="$2"; shift 2 ;;
    --group) GROUP_NAME="$2"; shift 2 ;;
    --cross-repo) CROSS_REPOS+=("$2"); shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

case "$MODE" in
  validate)
    run_validate
    exit $?
    ;;
  release)
    run_release
    ;;
  base)
    run_base
    ;;
  cross)
    if [[ ${#CROSS_REPOS[@]} -eq 0 ]]; then
      echo "ERROR:cross_repo:missing"
      exit 1
    fi
    parsed=$(parse_cross_entry "${CROSS_REPOS[0]}" "$BASE_BRANCH")
    run_cross "${parsed%%|*}" "${parsed##*|}"
    ;;
  all)
    VALIDATION_RC=0
    run_validate || VALIDATION_RC=$?
    if [[ $VALIDATION_RC -eq 1 ]]; then
      exit 1
    fi

    RELEASE_FAILED=0
    BASE_FAILED=0
    CROSS_FAILED=0
    CROSS_WARN=0
    CROSS_OK=0
    SUCCESS_CROSS_PATHS=()

    if ! run_release; then
      RELEASE_FAILED=1
    fi

    if ! run_base; then
      BASE_FAILED=1
    fi

    for entry in "${VALID_CROSS_REPOS[@]}"; do
      parsed=$(parse_cross_entry "$entry" "$BASE_BRANCH")
      cross_path="${parsed%%|*}"
      cross_branch="${parsed##*|}"

      cross_out=$(run_cross "$cross_path" "$cross_branch" 2>&1) || {
        echo "$cross_out"
        CROSS_FAILED=$((CROSS_FAILED + 1))
        continue
      }

      echo "$cross_out"
      if echo "$cross_out" | grep -q '^WARN:'; then
        CROSS_WARN=$((CROSS_WARN + 1))
      else
        CROSS_OK=$((CROSS_OK + 1))
      fi
      SUCCESS_CROSS_PATHS+=("$cross_path")
    done

    GROUP_STATUS="skipped"
    CROSS_LINKS=0
    if [[ $RELEASE_FAILED -eq 0 && ${#SUCCESS_CROSS_PATHS[@]} -gt 0 ]]; then
      group_out=$(run_group_sync "${SUCCESS_CROSS_PATHS[@]}" 2>&1) || true
      echo "$group_out"
      if echo "$group_out" | grep -q '^STATUS:group_synced:'; then
        GROUP_STATUS="ok"
        CROSS_LINKS=$(echo "$group_out" | grep '^STATUS:group_synced:' | tail -1 | sed -E 's/.*cross_links=([0-9]+).*/\1/')
      elif echo "$group_out" | grep -q '^STATUS:gitnexus_not_installed'; then
        GROUP_STATUS="skipped"
      else
        GROUP_STATUS="warn"
      fi
    fi

    if [[ "$GITNEXUS_AVAILABLE" != true ]]; then
      ANALYSIS_MODE="grep_fallback"
    elif [[ ${#SUCCESS_CROSS_PATHS[@]} -gt 0 && "$CROSS_LINKS" -gt 0 ]]; then
      ANALYSIS_MODE="gitnexus_group"
    elif [[ ${#SUCCESS_CROSS_PATHS[@]} -gt 0 ]]; then
      ANALYSIS_MODE="gitnexus_local_grep_cross"
    else
      ANALYSIS_MODE="gitnexus_local"
    fi

    if [[ $RELEASE_FAILED -eq 1 || $BASE_FAILED -eq 1 ]]; then
      echo "JOINPOINT:status=failed:release_failed=$RELEASE_FAILED:base_failed=$BASE_FAILED:cross_failed=$CROSS_FAILED:group=$GROUP_STATUS:analysis_mode=$ANALYSIS_MODE"
      exit 1
    fi

    echo "JOINPOINT:status=ok:cross_ok=$CROSS_OK:cross_warn=$CROSS_WARN:cross_failed=$CROSS_FAILED:group=$GROUP_STATUS:cross_links=$CROSS_LINKS:analysis_mode=$ANALYSIS_MODE"
    ;;
  *)
    echo "Unknown mode: $MODE"
    exit 1
    ;;
esac
