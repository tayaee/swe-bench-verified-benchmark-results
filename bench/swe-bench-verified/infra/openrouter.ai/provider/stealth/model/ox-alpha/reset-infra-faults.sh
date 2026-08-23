#!/usr/bin/env bash
# reset-infra-faults.sh — Reset infra-fault instances (e.g. OpenRouterRateLimitError)
# so ./run.sh retries them. Thin wrapper around reset-faults.sh; see it for details.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/reset-faults.sh" infra-faults "$@"
