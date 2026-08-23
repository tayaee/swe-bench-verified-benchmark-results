#!/usr/bin/env bash
# reset-engine-faults.sh — Reset engine-fault instances (harness/eval-side failures)
# so ./run.sh retries them. No statuses are mapped to this category yet — edit
# STATUS_TO_FAULT in reset-faults.sh as new ones are observed. Thin wrapper
# around reset-faults.sh; see it for details.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/reset-faults.sh" engine-faults "$@"
