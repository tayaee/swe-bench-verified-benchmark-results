#!/usr/bin/env bash
# eval.sh — Score stealth/ox-alpha predictions with swebench eval.
#
# Self-contained. Runs `swebench eval` on $WORKDIR/runs/<run_id>/preds.json
# and produces per-instance report.json files. Idempotent: instances that
# already have a report.json are skipped, so repeated invocations act as a
# resume. Designed to be called by ./run.sh (smoke mode), ./report.sh
# (live orchestration), or directly.
#
# Swebench log layout (HARDCODED relative path inside the harness):
#   $PROVIDER_DIR/logs/run_evaluation/<run_id>/<model>__/<instance_id>/report.json
# (<model>__ has "__" because the harness substitutes "/" with "__" in path
# segments.) The --report-dir flag only controls the run-summary JSON, NOT
# the per-instance reports.
#
# Usage:
#   ./eval.sh                       # --latest: newest run with preds.json
#   ./eval.sh <run_id>              # specific run (positional or --run-id)
#   ./eval.sh --instance <id> [...] # score only these instances (repeatable)
#   ./eval.sh --all                 # score every instance in preds.json
#   ./eval.sh --workers N           # default 4

set -euo pipefail

PROVIDER_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$PROVIDER_DIR/../.." && pwd)"
WORKDIR="$PROVIDER_DIR/swebench-work"

# shellcheck source=provider.env
source "$PROVIDER_DIR/provider.env"

# Per-instance reports land under $WORKDIR/logs/run_evaluation because
# `sb eval` runs with cwd=$WORKDIR (see "invoke sb eval" below).
LOG_BASE="$WORKDIR/logs/run_evaluation"

MAX_WORKERS=4
RUN_ID=""
INSTANCE_IDS=()
USE_ALL=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workers|-w) MAX_WORKERS="$2"; shift 2 ;;
    --instance)   INSTANCE_IDS+=("$2"); shift 2 ;;
    --run-id)     RUN_ID="$2"; shift 2 ;;
    --all)        USE_ALL=true; shift ;;
    --latest)     : ;;  # default behavior; kept for explicit usage
    -*)           echo "unknown option: $1" >&2; exit 1 ;;
    *)            RUN_ID="${RUN_ID:-$1}"; shift ;;
  esac
done

py() { uv run --project "$REPO_ROOT" python "$@"; }
sb() { uv run --project "$REPO_ROOT" swebench "$@"; }

# ---------------------------------------------------------------- resolve run-id
# Precedence: positional/--run-id > --latest (preds.json mtime newest).
if [[ -z "$RUN_ID" ]]; then
  runs_dir="$WORKDIR/runs"
  if [[ ! -d "$runs_dir" ]]; then
    echo "error: no runs directory at $runs_dir" >&2
    exit 1
  fi
  cands=()
  while IFS= read -r -d '' d; do
    [[ -f "$d/preds.json" ]] && cands+=("$(stat -c %Y "$d/preds.json" 2>/dev/null || echo 0)|$(basename "$d")")
  done < <(find "$runs_dir" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
  if [[ ${#cands[@]} -eq 0 ]]; then
    echo "error: no preds.json found under $runs_dir" >&2
    exit 1
  fi
  RUN_ID=$(printf '%s\n' "${cands[@]}" | sort -t'|' -k1nr | head -1 | cut -d'|' -f2-)
fi

pred_file="$WORKDIR/runs/$RUN_ID/preds.json"
if [[ ! -f "$pred_file" ]]; then
  echo "error: no preds.json at $pred_file (run '$RUN_ID' not found)" >&2
  exit 1
fi

# ---------------------------------------------------------------- resolve instance list
# Precedence: explicit --instance > --all > preds.json contents.
if [[ ${#INSTANCE_IDS[@]} -gt 0 ]]; then
  : # caller-supplied subset
elif $USE_ALL; then
  mapfile -t INSTANCE_IDS < <(py -c '
import json, sys
preds = json.load(open(sys.argv[1]))
# preds.json may be either a list of {instance_id, ...} or a dict
# {instance_id: prediction_data}; support both.
if isinstance(preds, dict):
    print("\n".join(preds.keys()))
else:
    print("\n".join(p["instance_id"] for p in preds))
' "$pred_file")
else
  mapfile -t INSTANCE_IDS < <(py -c '
import json, sys
preds = json.load(open(sys.argv[1]))
if isinstance(preds, dict):
    print("\n".join(preds.keys()))
else:
    print("\n".join(p["instance_id"] for p in preds))
' "$pred_file")
fi

if [[ ${#INSTANCE_IDS[@]} -eq 0 ]]; then
  echo "[eval] run $RUN_ID has no predictions to score"
  exit 0
fi

# ---------------------------------------------------------------- idempotent skip
# Skip instances whose per-instance report.json already exists under the
# HARDCODED log path. This makes repeated ./eval.sh invocations a resume.
to_eval=()
skipped=0
for iid in "${INSTANCE_IDS[@]}"; do
  report="$LOG_BASE/$RUN_ID/$LOG_MODEL_DIR/$iid/report.json"
  if [[ -s "$report" ]]; then
    skipped=$((skipped + 1))
  else
    to_eval+=("$iid")
  fi
done

echo "[eval] run=$RUN_ID workers=$MAX_WORKERS total=${#INSTANCE_IDS[@]} already_scored=$skipped to_score=${#to_eval[@]}"

if [[ ${#to_eval[@]} -eq 0 ]]; then
  echo "[eval] all instances already scored — nothing to do"
  exit 0
fi

# ---------------------------------------------------------------- invoke sb eval
# Pass --report-dir only for the run-summary JSON. Per-instance reports land
# under $PROVIDER_DIR/logs/run_evaluation regardless (see header comment).
cd "$WORKDIR"
eval_args=(verified
           --predictions "$pred_file"
           --run-id "$RUN_ID"
           --workers "$MAX_WORKERS"
           --report-dir "$WORKDIR/logs/run_evaluation")
for iid in "${to_eval[@]}"; do
  eval_args+=(--instance "$iid")
done

sb eval "${eval_args[@]}"
echo "[eval] scored ${#to_eval[@]} instance(s) — reports at $LOG_BASE/$RUN_ID/"
