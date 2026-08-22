#!/usr/bin/env bash
# clean.sh — Clean up test data produced by smoke tests / evaluation runs.
#
# Removes:
#   - swebench-work/          (predictions, harness logs, run outputs)
#   - SWE-bench eval containers left behind by the harness
#   - swebench Docker cache dirs (~/.swebench)            [with --docker]
#
# Usage:
#   ./clean.sh             # remove local run artifacts only
#   ./clean.sh --docker    # also remove leftover eval containers + ~/.swebench cache
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
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

echo "[clean] removing local run artifacts..."
rm_item "$ROOT/swebench-work"

if $WITH_DOCKER; then
  echo "[clean] removing leftover swebench containers..."
  if command -v docker >/dev/null && docker info >/dev/null 2>&1; then
    # containers named like sweb.eval.x86_64.<instance>...
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
