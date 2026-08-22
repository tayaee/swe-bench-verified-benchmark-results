#!/usr/bin/env bash
# smoke-test.sh — End-to-end smoke test for the SWE-bench Verified setup.
#
# Steps:
#   1. Check that Docker is available and running (the harness needs it).
#   2. Run run-swebench-verified.sh --limit-new-ok 1 --limit-max-try 10
#      (keep trying instances until 1 resolves, at most 10 new attempts).
#   3. Run eval.sh to confirm the score shows up (1 resolved out of 500).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

fail() { echo "[smoke-test] FAIL: $*" >&2; exit 1; }
pass() { echo "[smoke-test] PASS: $*"; }

# ---------------------------------------------------------------- 1. docker
echo "=== [1/3] Docker check ==="
command -v docker >/dev/null || fail "docker not installed"
docker info >/dev/null 2>&1 || fail "docker daemon not running"
pass "docker daemon is running"

# ------------------------------------------- 2. run until 1 success (max 10)
echo "=== [2/3] run-swebench-verified.sh --limit-new-ok 1 --limit-max-try 10 ==="
"$ROOT/run-swebench-verified.sh" -w 1 --limit-new-ok 1 --limit-max-try 10
pass "run finished (1 resolved within 10 attempts)"

# ------------------------------------------------------- 3. verify via eval
echo "=== [3/3] eval.sh score check ==="
EVAL_OUT="$("$ROOT/eval.sh" --all)"
echo "$EVAL_OUT"

echo "$EVAL_OUT" | grep -qE "resolved\s*:\s* *[1-9]" \
  || fail "eval.sh reports no resolved instance"

echo "$EVAL_OUT" | grep -qE "completed\s*:\s* *1\b" \
  && echo "[smoke-test] score is 1/500" \
  || echo "[smoke-test] note: completed count differs from 1, but at least 1 resolved"

pass "score confirmed: at least 1 resolved"
echo "[smoke-test] ALL CHECKS PASSED"
