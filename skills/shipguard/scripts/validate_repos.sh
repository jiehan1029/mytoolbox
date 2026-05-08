#!/bin/bash
# validate_repos.sh — compatibility wrapper
# Canonical implementation lives in provision_all.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/provision_all.sh" --mode validate "$@"
