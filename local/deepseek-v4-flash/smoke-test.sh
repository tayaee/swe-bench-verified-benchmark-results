#!/usr/bin/env bash
# smoke-test.sh — End-to-end smoke test for DeepSeek-V4-Flash (ds4-server).
#
# Self-contained. Assumes ds4-server is already running (start via
# ./serve/serve.sh in another shell). Steps:
#   1. ds4-server reachable at $OPENAI_API_BASE (/v1/models)
#   2. /v1/models advertises deepseek-v4-flash
#   3. /v1/chat/completions responds to a trivial prompt
#   4. ./run.sh resolves at least 1 of 5 instances

set -euo pipefail

PROVIDER_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=provider.env
source "$PROVIDER_DIR/provider.env"

# Materialize env vars (same logic as run.sh, so the preflight matches what
# the actual run will use).
if [[ -z "${!API_KEY_ENV:-}" ]]; then
  export "$API_KEY_ENV=$API_KEY_DEFAULT"
fi
if [[ -n "$API_BASE" ]]; then
  export OPENAI_API_BASE="$API_BASE"
fi

BASE="${OPENAI_API_BASE%/}"
MODEL_BARE="deepseek-v4-flash"

fail() { echo "[smoke-test:$PROVIDER_ID] FAIL: $*" >&2; exit 1; }
pass() { echo "[smoke-test:$PROVIDER_ID] PASS: $*"; }

# ---------------------------------------------------------------- 1. reachability
echo "=== [1/4] ds4-server reachable at $BASE ==="
command -v curl >/dev/null || fail "curl not installed"

models_resp="$(curl -fsS --max-time 5 "$BASE/models" 2>&1)" \
  || fail "GET $BASE/models failed: $models_resp"
pass "GET $BASE/models OK"

# ---------------------------------------------------------------- 2. model listed
echo "=== [2/4] /v1/models includes $MODEL_BARE ==="
if ! printf '%s' "$models_resp" | grep -q "$MODEL_BARE"; then
  echo "$models_resp" | head -c 500 >&2
  echo >&2
  fail "$MODEL_BARE not found in /v1/models"
fi
pass "$MODEL_BARE is advertised by ds4-server"

# ---------------------------------------------------------------- 3. trivial completion
echo "=== [3/4] /v1/chat/completions responds ==="
chat_resp="$(curl -fsS --max-time 60 "$BASE/chat/completions" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    -d "{\"model\":\"$MODEL_BARE\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with the single word: ok\"}],\"max_tokens\":8,\"temperature\":0}" \
    2>&1)" \
  || fail "POST $BASE/chat/completions failed: $chat_resp"
pass "completion returned $(printf '%s' "$chat_resp" | wc -c) bytes"

# ---------------------------------------------------------------- 4. end-to-end
echo "=== [4/4] ./run.sh --limit-new-ok 1 --limit-max-try 5 ==="
"$PROVIDER_DIR/run.sh" -w 1 --limit-new-ok 1 --limit-max-try 5
pass "run finished (1 resolved within 5 attempts)"

echo "[smoke-test:$PROVIDER_ID] ALL CHECKS PASSED"