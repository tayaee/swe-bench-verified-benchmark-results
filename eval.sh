#!/usr/bin/env bash
# eval.sh — Score SWE-bench evaluation logs in (near) real time.
#
# Usage:
#   ./eval.sh --live <run_id>     # keep polling and printing the running score
#   ./eval.sh --all               # score once, aggregating ALL runs found
#   ./eval.sh <run_id>            # score once for the given run
#   ./eval.sh                     # score once for the newest run found
#
# For every finished instance (a test_output.txt in the harness log dir) the
# per-instance test results are graded, and a running resolution rate is
# printed. When --live is given, this repeats every 30 s until the parent
# harness process disappears.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
: "${OPENROUTER_API_KEY:?error: OPENROUTER_API_KEY environment variable must be set}"
OX_ALPHA_MODEL_ID="stealth/ox-alpha"

MODE="${1:-once}"
RUN_ID="${2:-}"
[[ "$MODE" == "--all" ]] && { MODE=once; RUN_ID="--all"; }
LOG_BASE="$ROOT/swebench-work/logs/run_evaluation/$OX_ALPHA_MODEL_ID"
INTERVAL=30

# Use the swebench package via the project's uv-managed venv.
PY=python3
[[ -x "$ROOT/.venv/bin/python" ]] && PY="$ROOT/.venv/bin/python"

score_once() {
  "$PY" - "$LOG_BASE" "$RUN_ID" <<'EOF'
import glob, json, os, sys

log_base, run_id = sys.argv[1], sys.argv[2]

try:
    from swebench.metrics.report import get_eval_report_from_map  # newer API
except Exception:
    get_eval_report_from_map = None
try:
    from swebench.harness.run_evaluation import get_eval_report  # older API
except Exception:
    get_eval_report = None

if not os.path.isdir(log_base):
    sys.exit(0)

# aggregate over all runs if requested, else newest run if unspecified
if run_id == "--all":
    pass  # glob below picks up every run directory
elif not run_id:
    runs = sorted(d for d in os.listdir(log_base) if os.path.isdir(os.path.join(log_base, d)))
    if not runs:
        sys.exit(0)
    run_id = runs[-1]

if run_id == "--all":
    report_files = sorted(glob.glob(os.path.join(log_base, "*", "*", "report.json")))
else:
    report_files = sorted(glob.glob(os.path.join(log_base, run_id, "*", "report.json")))

resolved = failed = unresolved = 0
for report_path in report_files:
    test_out = os.path.join(os.path.dirname(report_path), "test_output.txt")
    inst_id = os.path.basename(os.path.dirname(test_out))
    try:
        if os.path.exists(report_path):
            rep = json.load(open(report_path))
        elif get_eval_report is not None:
            rep = get_eval_report(
                {"instance_id": inst_id, "model_patch": ""},
                None, test_out, apply_test_patch=False, log_dir=log_base,
            )
        else:
            continue
    except Exception:
        continue

    if rep.get("resolved"):
        resolved += 1
    elif rep.get("test_status") or rep.get("failure_report"):
        failed += 1
    else:
        unresolved += 1

done = resolved + failed + unresolved
if done == 0:
    sys.exit(0)

pct = lambda n: f"{n:3d} ({100.0 * n / done:5.1f}%)"
print(f"\n=== SWE-bench Verified LIVE SCORE — run: {run_id} ===")
print(f"  completed : {done}")
print(f"  resolved  : {pct(resolved)}")
print(f"  failed    : {pct(failed)}")
print(f"  unresolved: {pct(unresolved)}")
print(f"  >>> resolution rate: {100.0 * resolved / done:.1f}% <<<\n", flush=True)
EOF
}

if [[ "$MODE" == "--live" ]]; then
  echo "[eval] live scoring every ${INTERVAL}s (ctrl-c or parent exit stops it)"
  while true; do
    score_once || true
    sleep "$INTERVAL"
  done
else
  score_once
fi
