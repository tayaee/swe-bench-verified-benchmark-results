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
#   1. Sets up an isolated venv with mini-swe-agent + swebench installed.
#   2. Runs the multi-turn agent inference via mini-swe-agent on
#      SWE-bench Verified using the model stealth/ox-alpha via openrouter.ai.
#   3. Evaluates the produced predictions with the official swebench harness.
#   4. While instances complete, eval.sh recomputes the score in real time.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
: "${OPENROUTER_API_KEY:?error: OPENROUTER_API_KEY environment variable must be set}"
OX_ALPHA_MODEL_ID="stealth/ox-alpha"  # model id on openrouter.ai
MSWEA_CONFIG="$ROOT/swebench.yaml"    # mini-swe-agent config (OpenRouter model class etc.)

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
# uv run auto-creates/syncs .venv from pyproject.toml+uv.lock on every call,
# so a missing/broken venv self-heals instead of failing mid-run.
py() { uv run --project "$ROOT" python "$@"; }
sb() { uv run --project "$ROOT" swebench "$@"; }
msa() { uv run --project "$ROOT" python -m minisweagent.run.benchmarks.swebench "$@"; }
export PATH="$VENV/bin:$PATH"

echo "[run] model   : $OX_ALPHA_MODEL_ID (openrouter.ai, multi-turn via mini-swe-agent)"
echo "[run] workers : $MAX_WORKERS"
echo "[run] run_id  : $RUN_ID"
echo "[run] workdir : $WORKDIR"

cd "$WORKDIR"

# Run mini-swe-agent inference on one or more instances and emit preds.json
# under $out_dir. Then we feed that into the official swebench harness.
#
# Usage: run_inference <out_dir> [--filter REGEX] [--slice N:M]
run_inference() {
  local out_dir="$1"; shift
  mkdir -p "$out_dir"
  msa \
    --subset verified \
    --split test \
    --model "$OX_ALPHA_MODEL_ID" \
    --model-class minisweagent.models.openrouter_model.OpenRouterModel \
    -c "$MSWEA_CONFIG" \
    --output "$out_dir" \
    --workers "$MAX_WORKERS" \
    "$@"
}

# ------------------------------------------------------- smoke-test mode
if [[ -n "$LIMIT_NEW_OK" ]]; then
  echo "[smoke] target resolved: $LIMIT_NEW_OK, max attempts: $LIMIT_MAX_TRY"

  # instance ids from the dataset (Verified, deterministic order)
  mapfile -t INSTANCE_IDS < <(py -c '
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

    # step 1: multi-turn agent inference (mini-swe-agent in docker)
    out_dir="$WORKDIR/runs/$sub_run"
    if ! run_inference "$out_dir" --filter "^${iid}\$"; then
      echo "[smoke] inference failed for $iid, trying next"
      continue
    fi

    pred_file="$out_dir/preds.json"
    if [[ ! -s "$pred_file" ]]; then
      echo "[smoke] no predictions produced for $iid, trying next"
      continue
    fi

    # step 2: evaluation (build + run tests in docker)
    if ! sb eval verified \
        --predictions "$pred_file" \
        --run-id "$sub_run" \
        --instance "$iid" \
        --workers "$MAX_WORKERS" \
        --report-dir "$WORKDIR/logs/run_evaluation"; then
      echo "[smoke] harness failed for $iid, trying next"
      continue
    fi
    # mini-swe-agent writes summary results to <out_dir>/results.json
    results_file="$out_dir/results.json"
    if [[ -n "$results_file" ]] && py -c '
import json, sys
data = json.load(open(sys.argv[1]))
iid = sys.argv[2]
# mini-swe-agent writes a per-instance summary; resolved is True/False per instance
inst = data.get(iid) or next((v for v in data.values() if isinstance(v, dict) and v.get("instance_id") == iid), {})
sys.exit(0 if inst.get("resolved") else 1)
' "$results_file" "$iid" 2>/dev/null; then
      new_ok=$((new_ok + 1))
      echo "[smoke] RESOLVED ✓ ($new_ok/$LIMIT_NEW_OK)"
    fi
    echo "[smoke] progress: resolved=$new_ok target=$LIMIT_NEW_OK attempts=$tries"
  done

  echo "[smoke] finished: $new_ok resolved out of $tries attempted"
  [[ "$new_ok" -ge "$LIMIT_NEW_OK" ]] && exit 0 || exit 1
fi

# ------------------------------------------------------------- run harness
cd "$WORKDIR"

# step 1: multi-turn agent inference over SWE-bench Verified
OUT_DIR="$WORKDIR/runs/$RUN_ID"
MSA_ARGS=(--output "$OUT_DIR")
if [[ -n "$MAX_INSTANCES" ]]; then
  # Get just the first N instance ids and use --slice to select them
  FIRST_IDS=$(head -n "$MAX_INSTANCES" <(
    py -c '
from datasets import load_dataset
ds = load_dataset("princeton-nlp/SWE-bench_Verified", split="test")
for i in ds["instance_id"]:
    print(i)
')
  )
  MSA_ARGS+=(--filter "^(($(echo "$FIRST_IDS" | paste -sd '|' -)))\$")
fi
run_inference "$OUT_DIR" "${MSA_ARGS[@]}"

# step 2: evaluation
PRED_FILE="$OUT_DIR/preds.json"
EVAL_ARGS=(verified --predictions "$PRED_FILE" --run-id "$RUN_ID" --workers "$MAX_WORKERS"
           --report-dir "$WORKDIR/logs/run_evaluation")
if [[ -n "$MAX_INSTANCES" ]]; then
  for iid in $FIRST_IDS; do EVAL_ARGS+=(--instance "$iid"); done
fi

# live score in background while evaluation runs
"$ROOT/eval.sh" --live "$RUN_ID" &
LIVE_PID=$!
trap 'kill "$LIVE_PID" 2>/dev/null || true' EXIT

sb eval "${EVAL_ARGS[@]}"

wait "$LIVE_PID" 2>/dev/null || true
trap - EXIT

echo "[done] final reports: $WORKDIR/logs/run_evaluation/$OX_ALPHA_MODEL_ID/$RUN_ID/"
echo "[done] trajectories : $OUT_DIR/"
