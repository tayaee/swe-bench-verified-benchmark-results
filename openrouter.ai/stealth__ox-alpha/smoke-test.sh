#!/usr/bin/env bash
# smoke-test.sh — End-to-end smoke test for stealth/ox-alpha (OpenRouter).
#
# Self-contained. Steps:
#   1. Docker daemon is running
#   2. OPENROUTER_API_KEY is set
#   3. ./run.sh resolves at least 1 of 10 instances

set -euo pipefail

PROVIDER_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=provider.env
source "$PROVIDER_DIR/provider.env"

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

echo "=== [3/3] ./run.sh --limit-new-ok 1 --limit-max-try 10 ==="
"$PROVIDER_DIR/run.sh" -w 1 --limit-new-ok 1 --limit-max-try 10
pass "run finished (1 resolved within 10 attempts)"

echo "[smoke-test:$PROVIDER_ID] ALL CHECKS PASSED"