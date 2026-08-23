#!/usr/bin/env bash
# reset-client-faults.sh — Reset client-fault instances (no-traj: never ran locally)
# so ./run.sh retries them. Thin wrapper around reset-faults.sh; see it for details.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/reset-faults.sh" client-faults "$@"
