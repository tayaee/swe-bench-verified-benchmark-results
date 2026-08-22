#!/usr/bin/env bash
# eval.sh — Score swebench harness logs for stealth/ox-alpha runs.
#
# Self-contained. Swebench log layout (default swebench eval output):
#   $WORKDIR/logs/run_evaluation/<run_id>/<model>__/<instance_id>/report.json
# (<model>__ has "__" because the harness substitutes "/" with "__" in path segments.)
#
# Usage:
#   ./eval.sh                 # score the newest run for this provider
#   ./eval.sh <run_id>        # score one run
#   ./eval.sh --all           # aggregate every run under logs/
#   ./eval.sh --live [run_id] # poll every 30 s (parent exit stops it)

set -euo pipefail

PROVIDER_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$PROVIDER_DIR/../.." && pwd)"
WORKDIR="$PROVIDER_DIR/swebench-work"

# shellcheck source=provider.env
source "$PROVIDER_DIR/provider.env"

LOG_BASE="$WORKDIR/logs/run_evaluation"
INTERVAL=30

py() { uv run --project "$REPO_ROOT" python "$@"; }

MODE="once"
TARGET="--latest"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --live) MODE="live"; TARGET="${2:---latest}"; shift 2 ;;
    --all)  TARGET="--all"; shift ;;
    -*)     echo "unknown option: $1" >&2; exit 1 ;;
    *)      TARGET="$1"; shift ;;
  esac
done

score_once() {
  py - "$LOG_BASE" "$TARGET" <<'EOF'
import glob, json, os, sys

log_base, target = sys.argv[1], sys.argv[2]

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

# Resolve target → list of report.json paths
if target == "--all":
    report_files = sorted(glob.glob(os.path.join(log_base, "*", "*", "*", "report.json")))
elif target == "--latest":
    runs = sorted(d for d in os.listdir(log_base) if os.path.isdir(os.path.join(log_base, d)))
    if not runs:
        sys.exit(0)
    report_files = sorted(glob.glob(os.path.join(log_base, runs[-1], "*", "*", "report.json")))
else:
    report_files = sorted(glob.glob(os.path.join(log_base, target, "*", "*", "report.json")))

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

    inst = rep.get(inst_id)
    if not isinstance(inst, dict):
        inst = rep  # legacy fallback

    if inst.get("resolved"):
        resolved += 1
    elif inst.get("test_status") or inst.get("failure_report"):
        failed += 1
    else:
        unresolved += 1

done = resolved + failed + unresolved
if done == 0:
    sys.exit(0)

pct = lambda n: f"{n} ({100.0 * n / done:.1f}%)"
print(f"\n=== SWE-bench Verified SCORE — provider: $PROVIDER_ID ===")
print(f"  completed     : {done}")
print(f"  resolved      : {pct(resolved)}")
print(f"  failed        : {pct(failed)}")
print(f"  unresolved    : {pct(unresolved)}")
print(f"  resolved rate : {resolved}/{done}")
print(f"  score         : {resolved}/500")
EOF
}

if [[ "$MODE" == "live" ]]; then
  echo "[eval] live scoring every ${INTERVAL}s (ctrl-c or parent exit stops it)"
  while true; do
    score_once || true
    sleep "$INTERVAL"
  done
else
  score_once
fi