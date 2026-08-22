#!/usr/bin/env bash
# smoke-test.sh — End-to-end smoke test for stealth/ox-alpha (OpenRouter).
#
# Self-contained. Steps:
#   1. Docker daemon is running
#   2. OPENROUTER_API_KEY is set
#   3. ./run.sh resolves a pinned, known-easy instance end-to-end
#
# The smoke-test pins a single instance that has been empirically observed
# to resolve reliably for stealth/ox-alpha on OpenRouter (recorded during
# earlier runs under logs/run_evaluation/). Pinning avoids the flake that
# comes from "try the first 10 unverified instances and hope one resolves".

set -euo pipefail

PROVIDER_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=provider.env
source "$PROVIDER_DIR/provider.env"

# Known-easy pinned instance. Recorded in logs/run_evaluation/ — see the
# resolved_ids lists in swebench-work/logs/run_evaluation/*.json. Replace
# this with another instance that has been observed to resolve if the
# current one ever stops being reliable.
SMOKE_INSTANCE="${SMOKE_INSTANCE:-astropy__astropy-12907}"

fail() { echo "[smoke-test:$PROVIDER_ID] FAIL: $*" >&2; exit 1; }
pass() { echo "[smoke-test:$PROVIDER_ID] PASS: $*"; }

echo "=== [1/3] Docker check ==="
command -v docker >/dev/null || fail "docker not installed"
docker info >/dev/null 2>&1 || fail "docker daemon not running"
pass "docker daemon is running"

echo "=== [2/3] $API_KEY_ENV check ==="
if [[ -z "${!API_KEY_ENV:-}" ]]; then
  fail "$API_KEY_ENV must be set in the environment"
fi
pass "$API_KEY_ENV is set (length=${#OPENROUTER_API_KEY})"

echo "=== [3/3] ./run.sh --instance $SMOKE_INSTANCE --limit-new-ok 1 ==="
if ! "$PROVIDER_DIR/run.sh" \
    -w 1 \
    --instance "$SMOKE_INSTANCE" \
    --limit-new-ok 1 \
    --limit-max-try 1; then
  fail "run.sh did not resolve $SMOKE_INSTANCE within 1 attempt"
fi
pass "run.sh resolved $SMOKE_INSTANCE"

echo "[smoke-test:$PROVIDER_ID] ALL CHECKS PASSED"