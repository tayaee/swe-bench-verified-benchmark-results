#!/usr/bin/env bash
# report.sh — Score swebench harness logs for stealth/ox-alpha runs.
#
# Self-contained. Reads per-instance report.json from
#   $PROVIDER_DIR/logs/run_evaluation/<run_id>/<model>__/<instance_id>/report.json
# and prints resolved/failed/unresolved counts. If a target run has predictions
# in preds.json but no eval report for some instances, ./eval.sh is invoked
# first to fill them in, so a single `./report.sh` call always returns a
# complete score for the requested run.
#
# Usage:
#   ./report.sh                  # --latest (newest run with preds.json)
#   ./report.sh <run_id>         # specific run (positional or --run-id)
#   ./report.sh --all            # aggregate every run under logs/run_evaluation/
#   ./report.sh --live [run_id]  # poll every 30 s (parent exit stops it)
#   ./report.sh --no-eval        # skip the implicit ./eval.sh trigger
#   ./report.sh --workers N      # workers passed to ./eval.sh when triggered

set -euo pipefail

PROVIDER_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$PROVIDER_DIR/../.." && pwd)"
WORKDIR="$PROVIDER_DIR/swebench-work"

# shellcheck source=provider.env
source "$PROVIDER_DIR/provider.env"

# swebench writes per-instance reports (report.json) under a relative
# `logs/run_evaluation/` path resolved against its current working directory
# ($WORKDIR at eval time). --report-dir only controls the run-summary JSON.
LOG_BASE="$WORKDIR/logs/run_evaluation"
INTERVAL=30
EVAL_WORKERS=4

MODE="once"
TARGET="--latest"
DO_EVAL=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --live)          MODE="live"; TARGET="${2:---latest}"; shift 2 ;;
    --all)           TARGET="--all"; shift ;;
    --no-eval)       DO_EVAL=false; shift ;;
    --workers|-w)    EVAL_WORKERS="$2"; shift 2 ;;
    --run-id)        TARGET="$2"; shift 2 ;;
    --latest)        TARGET="--latest"; shift ;;
    -*)              echo "unknown option: $1" >&2; exit 1 ;;
    *)               TARGET="$1"; shift ;;
  esac
done

py() { uv run --project "$REPO_ROOT" python "$@"; }

# ---------------------------------------------------------------- resolve target
# Returns either a concrete run_id, "--all", or "" (no candidates).
resolve_target() {
  case "$TARGET" in
    --all)
      echo "--all"
      return
      ;;
    --latest)
      # Prefer newest run with preds.json (inference footprint wins over
      # stale log dirs from a deleted run).
      local runs_dir="$WORKDIR/runs" cands=()
      if [[ -d "$runs_dir" ]]; then
        while IFS= read -r -d '' d; do
          [[ -f "$d/preds.json" ]] && cands+=("$(stat -c %Y "$d/preds.json" 2>/dev/null || echo 0)|$(basename "$d")")
        done < <(find "$runs_dir" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
        if [[ ${#cands[@]} -gt 0 ]]; then
          printf '%s\n' "${cands[@]}" | sort -t'|' -k1nr | head -1 | cut -d'|' -f2-
          return
        fi
      fi
      # Fallback: newest run dir under LOG_BASE (smoke test artefacts only).
      if [[ -d "$LOG_BASE" ]]; then
        local last
        last=$(ls -1 "$LOG_BASE" 2>/dev/null | grep -v '^\.' | sort | tail -1 || true)
        if [[ -n "$last" ]]; then
          echo "$last"
          return
        fi
      fi
      echo ""
      ;;
    *)
      echo "$TARGET"
      ;;
  esac
}

# ---------------------------------------------------------------- ensure_eval
# If the target run has predictions missing eval reports, invoke ./eval.sh
# to fill them in. Skipped entirely when --all or --no-eval.
ensure_eval() {
  local run_id="$1"
  $DO_EVAL || { echo "[report] --no-eval set, skipping implicit eval"; return; }

  local pred_file="$WORKDIR/runs/$run_id/preds.json"
  if [[ ! -f "$pred_file" ]]; then
    echo "[report] no preds.json at $pred_file — nothing to score"
    return
  fi

  # Collect instance_ids in preds.json whose report.json is missing.
  local missing=()
  while IFS= read -r iid; do
    [[ -z "$iid" ]] && continue
    local report="$LOG_BASE/$run_id/$LOG_MODEL_DIR/$iid/report.json"
    if [[ ! -s "$report" ]]; then
      missing+=("$iid")
    fi
  done < <(py -c '
import json, sys
preds = json.load(open(sys.argv[1]))
# preds.json may be either a list of {instance_id, ...} or a dict
# {instance_id: prediction_data}; support both.
if isinstance(preds, dict):
    print("\n".join(preds.keys()))
else:
    print("\n".join(p["instance_id"] for p in preds))
' "$pred_file")

  if [[ ${#missing[@]} -eq 0 ]]; then
    echo "[report] run=$run_id: all predictions already scored"
    return
  fi

  echo "[report] run=$run_id: scoring ${#missing[@]} missing instance(s) via ./eval.sh"
  local args=(--run-id "$run_id" --workers "$EVAL_WORKERS")
  for iid in "${missing[@]}"; do args+=(--instance "$iid"); done
  "$PROVIDER_DIR/eval.sh" "${args[@]}"
}

# ---------------------------------------------------------------- aggregate
# Provider label relative to ~/git (falls back to absolute path).
PROVIDER_LABEL="$PROVIDER_DIR"
[[ "$PROVIDER_DIR" == "$HOME/git/"* ]] && PROVIDER_LABEL="${PROVIDER_DIR#"$HOME/git/"}"

score_once() {
  py - "$LOG_BASE" "$TARGET" "$PROVIDER_LABEL" "$WORKDIR" "$PROVIDER_ID" <<'EOF'
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
# `./report.sh <run_id>` show the inference footprint even before
# `eval.sh` finishes.
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
                    f"unresolved. Run 'eval.sh' to actually evaluate them."
                )
        except Exception:
            pass

done = resolved + failed + unresolved
if done == 0:
    sys.exit(0)

TOTAL = 500

# Count predictions for the run. Preds without an eval report are of
# unknown status from here — queued, currently running, or lost — so we
# can't tell them apart; label them honestly as in-progress/unknown.
n_preds = 0
if run_id is not None:
    preds_path = os.path.join(workdir, "runs", run_id, "preds.json")
    if os.path.exists(preds_path):
        try:
            preds = json.load(open(preds_path))
            n_preds = len(preds) if hasattr(preds, "__len__") else 0
        except Exception:
            n_preds = 0
pending = max(n_preds - done, 0)
unvisited = TOTAL - done - pending

pct = lambda num, den: f"{100.0 * num / den:.1f}%"
est = pct(resolved, done) if done else "n/a"
finished = pending == 0 and unvisited == 0
print(f"\n=== SWE-bench Verified SCORE — provider: {provider_dir} ===")
print(f"  run_id        : {run_id or '(all)'}")
if fallback_note:
    print(f"  note          : {fallback_note}")
print(f"  {TOTAL} total")
print(f"     +-- {done} completed")
print(f"     |    +-- {resolved} resolved")
print(f"     |    |   +-- {failed} failed")
print(f"     |    |   +-- {unresolved} unresolved")
print(f"     |    +-- {pending} in-progress or unknown")
print(f"     +-- {unvisited} unvisited")
print(f"  progress       : {pct(done, TOTAL)} ({done}/{TOTAL} completed/total)")
print(f"  score estimate : {est} ({resolved}/{done} resolved/completed)")
suffix = "" if finished else " - in progress"
print(f"  score final    : {pct(resolved, TOTAL)} ({resolved}/{TOTAL} resolved/total){suffix}")
EOF
}

# ---------------------------------------------------------------- dispatch
case "$MODE" in
  live)
    echo "[report] live scoring every ${INTERVAL}s (ctrl-c to stop)"
    while true; do
      target=$(resolve_target)
      if [[ "$target" != "--all" && -n "$target" ]]; then
        ensure_eval "$target" || true
      fi
      score_once || true
      sleep "$INTERVAL"
    done
    ;;
  once)
    target=$(resolve_target)
    if [[ -z "$target" ]]; then
      echo "error: --latest found no runs (no preds.json in $WORKDIR/runs and no dirs in $LOG_BASE)" >&2
      exit 1
    fi
    if [[ "$target" != "--all" ]]; then
      ensure_eval "$target"
    fi
    score_once
    ;;
esac
