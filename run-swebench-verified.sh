#!/usr/bin/env bash
# run-swebench-verified.sh — Run the ox-alpha model (openrouter.ai) on
# SWE-bench Verified and produce a live score while it runs.
#
# Usage:
#   ./run-swebench-verified.sh [max_instances] [-w workers]
#   ./run-swebench-verified.sh --limit-new-ok N [--limit-max-try M]
#
# Smoke-test mode (--limit-new-ok): keep trying fresh instances one at a
# time until N of them resolve successfully. --limit-max-try caps the total
# number of NEW attempts (default 10).
#
# What it does:
#   1. Sets up an isolated venv with swebench installed.
#   2. Runs inference + evaluation over SWE-bench Verified using the
#      model stealth/ox-alpha via openrouter.ai.
#   3. While instances complete, eval.sh recomputes the score in real time.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
: "${OPENROUTER_API_KEY:?error: OPENROUTER_API_KEY environment variable must be set}"
OX_ALPHA_MODEL_ID="stealth/ox-alpha"  # model id on openrouter.ai

MAX_INSTANCES=""                     # empty = all 500
MAX_WORKERS=4                        # parallel workers (-w)
LIMIT_NEW_OK=""                      # smoke mode: stop after N resolved
LIMIT_MAX_TRY=10                     # smoke mode: max new attempts

while [[ $# -gt 0 ]]; do
  case "$1" in
    -w) MAX_WORKERS="$2"; shift 2 ;;
    --limit-new-ok)  LIMIT_NEW_OK="$2"; shift 2 ;;
    --limit-max-try) LIMIT_MAX_TRY="$2"; shift 2 ;;
    -*) echo "unknown option: $1" >&2; exit 1 ;;
    *)  MAX_INSTANCES="$1"; shift ;;
  esac
done

RUN_ID="ox-alpha-$(date +%Y%m%d-%H%M%S)"

VENV="$ROOT/.venv"
WORKDIR="$ROOT/swebench-work"
mkdir -p "$WORKDIR"

# ---------------------------------------------------------------- env setup (uv)
command -v uv >/dev/null || { echo "error: uv not found" >&2; exit 1; }
if [[ ! -x "$VENV/bin/python" ]]; then
  echo "[setup] creating venv with uv at $VENV"
  (cd "$ROOT" && uv sync --project "$ROOT")
fi
export PATH="$VENV/bin:$PATH"

echo "[run] model   : $OX_ALPHA_MODEL_ID (openrouter.ai)"
echo "[run] workers : $MAX_WORKERS"
echo "[run] run_id  : $RUN_ID"
echo "[run] workdir : $WORKDIR"

cd "$WORKDIR"

# ------------------------------------------------------- smoke-test mode
if [[ -n "$LIMIT_NEW_OK" ]]; then
  echo "[smoke] target resolved: $LIMIT_NEW_OK, max attempts: $LIMIT_MAX_TRY"

  # instance ids from the dataset (Verified, deterministic order)
  mapfile -t INSTANCE_IDS < <("$VENV/bin/python" -c '
from datasets import load_dataset
ds = load_dataset("princeton-nlp/SWE-bench_Verified", split="test")
for i in ds["instance_id"]:
    print(i)
')

  new_ok=0; tries=0
  for iid in "${INSTANCE_IDS[@]}"; do
    (( tries >= LIMIT_MAX_TRY )) && break
    (( new_ok >= LIMIT_NEW_OK )) && break
    (( tries > 0 )) && sleep 5
    tries=$((tries + 1))
    sub_run="$RUN_ID-smoke-$tries"
    echo "[smoke] attempt $tries/$LIMIT_MAX_TRY : $iid"

    # step 1: inference for this single instance
    pred_file="$WORKDIR/predictions/$sub_run.jsonl"
    if ! "$VENV/bin/python" "$ROOT/predict.py" \
        --instance_ids "$iid" --out "$pred_file" --model "$OX_ALPHA_MODEL_ID"; then
      echo "[smoke] prediction failed for $iid, trying next"
      continue
    fi

    # step 2: evaluation (build + run tests in docker)
    if ! python -m swebench.harness.run_evaluation \
        --dataset_name princeton-nlp/SWE-bench_Verified \
        --run_id "$sub_run" \
        --predictions_path "$pred_file" \
        --instance_ids "$iid" \
        --max_workers "$MAX_WORKERS"; then
      echo "[smoke] harness failed for $iid, trying next"
      continue
    fi
    report="$WORKDIR/logs/run_evaluation/$OX_ALPHA_MODEL_ID/$sub_run/report.json"
    if [[ ! -f "$report" ]]; then
      # newer swebench writes reports under a flat dir
      report=$(find "$WORKDIR/logs/run_evaluation" -path "*$sub_run*report.json" 2>/dev/null | head -n1 || true)
    fi
    if [[ -n "$report" ]] && "$VENV/bin/python" -c '
import json, sys
rep = json.load(open(sys.argv[1]))
r = rep.get(sys.argv[2], {})
sys.exit(0 if r.get("resolved") or any(v.get("resolved") for v in rep.values()) else 1)
' "$report" "$iid" 2>/dev/null; then
      new_ok=$((new_ok + 1))
      echo "[smoke] RESOLVED ✓ ($new_ok/$LIMIT_NEW_OK)"
    fi
    echo "[smoke] progress: resolved=$new_ok target=$LIMIT_NEW_OK attempts=$tries"
  done

  echo "[smoke] finished: $new_ok resolved out of $tries attempted"
  exit 0
fi

# ------------------------------------------------------------- run harness
cd "$WORKDIR"

# step 1: inference — generate predictions via litellm/openrouter
PRED_FILE="$WORKDIR/predictions/full.jsonl"
PRED_ARGS=(--out "$PRED_FILE" --model "$OX_ALPHA_MODEL_ID")
if [[ -n "$MAX_INSTANCES" ]]; then
  PRED_IDS=$(head -n "$MAX_INSTANCES" <(
    "$VENV/bin/python" -c '
from datasets import load_dataset
ds = load_dataset("princeton-nlp/SWE-bench_Verified", split="test")
for i in ds["instance_id"]:
    print(i)
')
  )
  PRED_ARGS+=(--instance_ids $PRED_IDS)
fi
"$VENV/bin/python" "$ROOT/predict.py" "${PRED_ARGS[@]}"

# step 2: evaluation
ARGS=(
  --dataset_name princeton-nlp/SWE-bench_Verified
  --run_id "$RUN_ID"
  --predictions_path "$PRED_FILE"
  --max_workers "$MAX_WORKERS"
)
if [[ -n "$MAX_INSTANCES" ]]; then
  PRED_IDS=$(head -n "$MAX_INSTANCES" <(
    "$VENV/bin/python" -c '
from datasets import load_dataset
ds = load_dataset("princeton-nlp/SWE-bench_Verified", split="test")
for i in ds["instance_id"]:
    print(i)
')
  )
  ARGS+=(--instance_ids $PRED_IDS)
fi

# live score in background while evaluation runs
"$ROOT/eval.sh" --live "$RUN_ID" &
LIVE_PID=$!
trap 'kill "$LIVE_PID" 2>/dev/null || true' EXIT

"$VENV/bin/python" -m swebench.harness.run_evaluation "${ARGS[@]}"

wait "$LIVE_PID" 2>/dev/null || true
trap - EXIT

echo "[done] final reports: $WORKDIR/logs/run_evaluation/$OX_ALPHA_MODEL_ID/$RUN_ID/"
