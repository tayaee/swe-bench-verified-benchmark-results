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

# swebench writes per-instance reports (report.json) under a HARDCODED
# `logs/run_evaluation/` relative path in the harness constants, regardless
# of --report-dir (which only controls the run-summary JSON). The actual
# per-instance logs therefore land at $PROVIDER_DIR/logs/run_evaluation,
# not under $WORKDIR — reading from the latter yields an empty report list.
LOG_BASE="$PROVIDER_DIR/logs/run_evaluation"
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
  # Args: LOG_BASE TARGET PROVIDER_DIR WORKDIR PROVIDER_ID
  py - "$LOG_BASE" "$TARGET" "$PROVIDER_DIR" "$WORKDIR" "$PROVIDER_ID" <<'EOF'
import glob, json, os, sys

log_base, target, provider_dir, workdir, provider_id = sys.argv[1:6]

try:
    from swebench.metrics.report import get_eval_report_from_map  # newer API
except Exception:
    get_eval_report_from_map = None
try:
    from swebench.harness.run_evaluation import get_eval_report  # older API
except Exception:
    get_eval_report = None

# ---------------------------------------------------------------- run-id resolution
# Resolve which run we are scoring, plus the list of per-instance report.json
# files. After this block: `run_id` is the canonical run name (or None for
# --all), `report_files` is the glob of per-instance report.json paths.
run_id = None
report_files = []

if target == "--all":
    report_files = sorted(glob.glob(os.path.join(log_base, "*", "*", "*", "report.json")))
elif target == "--latest":
    runs = []
    if os.path.isdir(log_base):
        runs = sorted(d for d in os.listdir(log_base)
                      if os.path.isdir(os.path.join(log_base, d)))
    if runs:
        run_id = runs[-1]
        report_files = sorted(glob.glob(os.path.join(log_base, runs[-1], "*", "*", "report.json")))
    else:
        # No per-instance log dirs (e.g. smoke test artefacts deleted). Pick the
        # newest run dir under WORKDIR/runs/ as the "latest" candidate.
        runs_dir = os.path.join(workdir, "runs")
        if os.path.isdir(runs_dir):
            cands = []
            for d in os.listdir(runs_dir):
                p = os.path.join(runs_dir, d, "preds.json")
                if os.path.isfile(p):
                    cands.append((os.path.getmtime(p), d))
            if cands:
                cands.sort()
                run_id = cands[-1][1]
else:
    run_id = target
    if os.path.isdir(log_base):
        report_files = sorted(glob.glob(os.path.join(log_base, target, "*", "*", "report.json")))

# ---------------------------------------------------------------- aggregate reports
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

# ---------------------------------------------------------------- fallback 1: run-summary JSON
# swebench writes a single `<provider_id>.<run_id>.json` summary next to the
# per-instance reports. Use it when per-instance reports are absent.
fallback_note = None
if (resolved + failed + unresolved) == 0 and run_id is not None:
    summary_path = os.path.join(
        workdir, "logs", "run_evaluation", f"{provider_id}.{run_id}.json"
    )
    if os.path.exists(summary_path):
        try:
            data = json.load(open(summary_path))
            resolved = int(data.get("resolved_instances", 0))
            completed = int(data.get("completed_instances", 0))
            unresolved = max(completed - resolved, 0)
            fallback_note = f"used run-summary {os.path.basename(summary_path)}"
        except Exception:
            pass

# ---------------------------------------------------------------- fallback 2: preds.json
# Final fallback: if no eval ran (or was deleted), count predictions in
# WORKDIR/runs/<run_id>/preds.json and report them as unresolved. This lets
# `./eval.sh run-1` show the inference footprint even before `sb eval` finishes.
if (resolved + failed + unresolved) == 0 and run_id is not None:
    preds_path = os.path.join(workdir, "runs", run_id, "preds.json")
    if os.path.exists(preds_path):
        try:
            preds = json.load(open(preds_path))
            n = len(preds) if hasattr(preds, "__len__") else 0
            if n > 0:
                unresolved = n
                fallback_note = (
                    f"no report.json or run-summary found — counted {n} "
                    f"prediction(s) in runs/{run_id}/preds.json as "
                    f"unresolved. Run 'sb eval' to actually evaluate them."
                )
        except Exception:
            pass

done = resolved + failed + unresolved
if done == 0:
    sys.exit(0)

pct = lambda n: f"{n} ({100.0 * n / done:.1f}%)"
print(f"\n=== SWE-bench Verified SCORE — provider: {provider_dir} ===")
print(f"  run_id        : {run_id or '(all)'}")
if fallback_note:
    print(f"  note          : {fallback_note}")
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
