#!/usr/bin/env bash
# clean.sh — Remove this provider's runtime artifacts.
#
# Self-contained. Removes:
#   - $PROVIDER_DIR/swebench-work/    (predictions, harness logs, run outputs)
#   - leftover swebench eval Docker containers           [with --docker]
#   - swebench Docker cache dirs (~/.swebench)           [with --docker]
#
# Usage:
#   ./clean.sh             # remove local run artifacts only
#   ./clean.sh --docker    # also remove leftover containers + ~/.swebench cache

set -euo pipefail

PROVIDER_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKDIR="$PROVIDER_DIR/swebench-work"

# shellcheck source=provider.env
source "$PROVIDER_DIR/provider.env"

WITH_DOCKER=false
[[ "${1:-}" == "--docker" ]] && WITH_DOCKER=true

removed=0
rm_item() {
  if [[ -e "$1" ]]; then
    echo "  removing: $1"
    rm -rf "$1"
    removed=$((removed + 1))
  fi
}

echo "[clean] removing runtime artifacts for $PROVIDER_ID..."
rm_item "$WORKDIR"

if $WITH_DOCKER; then
  echo "[clean] removing leftover swebench containers..."
  if command -v docker >/dev/null && docker info >/dev/null 2>&1; then
    CIDS=$(docker ps -aq --filter "name=sweb.eval" 2>/dev/null || true)
    if [[ -n "$CIDS" ]]; then
      docker rm -f $CIDS >/dev/null
      echo "  removed $(wc -w <<<"$CIDS") container(s)"
      removed=$((removed + 1))
    else
      echo "  no leftover containers"
    fi
  else
    echo "  [skip] docker not available"
  fi

  echo "[clean] removing ~/.swebench cache..."
  rm_item "$HOME/.swebench"
fi

echo "[clean] done ($removed item(s) removed)"