#!/usr/bin/env bash
# run.sh — Run stealth/ox-alpha (OpenRouter) on SWE-bench Verified.
#
# Self-contained: sources only files in this directory and the project
# root's pyproject.toml (uv-managed dependency manifest). No other scripts
# outside this directory are referenced.
#
# Usage:
#   ./run.sh                          # all 500 instances, 4 workers
#   ./run.sh [max_instances] [-w workers]
#   ./run.sh --limit-new-ok N [--limit-max-try M]
#   ./run.sh --limit-new-ok N --instance <id>   # smoke-test a single instance
#
# Smoke-test mode (--limit-new-ok): keep trying fresh instances one at a
# time until N of them resolve successfully. --limit-max-try caps the total
# number of NEW attempts (default 10). With --instance, restrict to that
# single instance (smoke-test.sh uses this to pin a known-easy case).

set -euo pipefail

PROVIDER_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$PROVIDER_DIR/../.." && pwd)"
WORKDIR="$PROVIDER_DIR/swebench-work"
mkdir -p "$WORKDIR"

# ---------------------------------------------------------------- provider.env
# shellcheck source=provider.env
source "$PROVIDER_DIR/provider.env"

# Materialize auth env var (required for OpenRouter; no default).
if [[ -n "${!API_KEY_ENV:-}" ]]; then
  : # already set by the caller
elif [[ -n "$API_KEY_DEFAULT" ]]; then
  export "$API_KEY_ENV=$API_KEY_DEFAULT"
else
  echo "error: $API_KEY_ENV must be set in the environment" >&2
  exit 1
fi

export MSWEA_COST_TRACKING="${MSWEA_COST_TRACKING:-ignore_errors}"

# ---------------------------------------------------------------- CLI parsing
MAX_INSTANCES=500
MAX_WORKERS=4
LIMIT_NEW_OK=""
LIMIT_MAX_TRY=10
SMOKE_INSTANCE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -w)                MAX_WORKERS="$2"; shift 2 ;;
    --limit-new-ok)    LIMIT_NEW_OK="$2"; shift 2 ;;
    --limit-max-try)   LIMIT_MAX_TRY="$2"; shift 2 ;;
    --max-instances)   MAX_INSTANCES="$2"; shift 2 ;;
    --instance)        SMOKE_INSTANCE="$2"; shift 2 ;;
    -*)                echo "unknown option: $1" >&2; exit 1 ;;
    *)                 MAX_INSTANCES="${MAX_INSTANCES:-$1}"; shift ;;
  esac
done

# Default to a fixed RUN_ID so re-running ./run.sh accumulates into the same
# output directory. Both backends (mini-swe-agent and swebench harness) treat
# existing artifacts (preds.json / report.json) as already done and skip them,
# so repeated invocations of ./run.sh act as a resume — new instances get
# processed, finished ones are left alone.
#
# Override per-run with `RUN_ID=experiment-42 ./run.sh` if you want isolation.
RUN_ID="${RUN_ID:-run-1}"

# ---------------------------------------------------------------- uv helpers
# uv run auto-creates/syncs .venv from $REPO_ROOT/pyproject.toml+uv.lock on
# every call, so a missing/broken venv self-heals instead of failing mid-run.
py()  { uv run --project "$REPO_ROOT" python "$@"; }
sb()  { uv run --project "$REPO_ROOT" swebench "$@"; }
msa() { uv run --project "$REPO_ROOT" python -m minisweagent.run.benchmarks.swebench "$@"; }
export PATH="$REPO_ROOT/.venv/bin:$PATH"

# ---------------------------------------------------------------- banner
echo "[run] provider : $PROVIDER_ID"
echo "[run] model    : $MODEL_ID ($MODEL_CLASS)"
echo "[run] endpoint : ${API_BASE:-<provider-default>}"
echo "[run] workers  : $MAX_WORKERS"
echo "[run] run_id   : $RUN_ID"
echo "[run] workdir  : $WORKDIR"

# ---------------------------------------------------------------- inference
# Run mini-swe-agent on one or more instances and emit preds.json under $out_dir.
#
# -c is order-sensitive: defaults first, our overrides last (recursive merge).
# Without the default config, mini-swe-agent's AgentConfig pydantic validation
# fails with "system_template: Field required" because -c REPLACES the default.
run_inference() {
  local out_dir="$1"; shift
  mkdir -p "$out_dir"
  msa \
    --subset verified \
    --split test \
    --model "$MODEL_ID" \
    --model-class "$MODEL_CLASS" \
    -c benchmarks/swebench.yaml \
    -c "$MSA_CONFIG" \
    --output "$out_dir" \
    --workers "$MAX_WORKERS" \
    "$@"
}

# ---------------------------------------------------------------- smoke mode
# Wait for any leftover minisweagent-* container to be cleaned up.
#
# msa's DockerEnvironment.cleanup() runs `docker stop` in the background
# (subprocess.Popen + &), so a container can briefly outlive the
# inference process. The smoke loop's invariant is at most one docker
# container at a time; without this wait, the eval container and the
# still-stopping inference container overlap. We poll docker ps with a
# short timeout — if cleanup stalls we log a warning and proceed so a
# stuck container doesn't deadlock the smoke test.
wait_msa_clean() {
  local i=60
  while (( i-- > 0 )); do
    if ! docker ps -q --filter "name=minisweagent" 2>/dev/null | grep -q .; then
      return 0
    fi
    sleep 1
  done
  echo "[smoke] warning: minisweagent container(s) still alive after 60s" >&2
  return 1
}

# Keep trying fresh instances one at a time until $LIMIT_NEW_OK resolve.
run_smoke() {
  echo "[smoke] target resolved: $LIMIT_NEW_OK, max attempts: $LIMIT_MAX_TRY"
  if [[ -n "$SMOKE_INSTANCE" ]]; then
    echo "[smoke] pinned instance: $SMOKE_INSTANCE"
  fi

  if [[ -n "$SMOKE_INSTANCE" ]]; then
    # Pin to a single instance (smoke-test.sh uses this to test a known-easy
    # case). Validate it exists in the dataset; bail early if not.
    mapfile -t INSTANCE_IDS < <(py -c '
import sys
from datasets import load_dataset
ds = load_dataset("princeton-nlp/SWE-bench_Verified", split="test")
want = sys.argv[1]
ids = [i for i in ds["instance_id"] if i == want]
if not ids:
    print(f"ERROR: instance {want!r} not found in SWE-bench Verified", file=sys.stderr)
    sys.exit(2)
for i in ids:
    print(i)
' "$SMOKE_INSTANCE")
    [[ ${#INSTANCE_IDS[@]} -gt 0 ]] || exit 2
    LIMIT_MAX_TRY=1
  else
    mapfile -t INSTANCE_IDS < <(py -c '
from datasets import load_dataset
ds = load_dataset("princeton-nlp/SWE-bench_Verified", split="test")
for i in ds["instance_id"]:
    print(i)
')
  fi

  local new_ok=0 tries=0 iid sub_run out_dir pred_file report
  for iid in "${INSTANCE_IDS[@]}"; do
    (( tries >= LIMIT_MAX_TRY )) && break
    (( new_ok >= LIMIT_NEW_OK )) && break
    (( tries > 0 )) && sleep 5
    tries=$((tries + 1))
    sub_run="$RUN_ID-smoke-$tries"
    echo "[smoke] attempt $tries/$LIMIT_MAX_TRY : $iid"

    # step 1: multi-turn agent inference
    out_dir="$WORKDIR/runs/$sub_run"
    if ! run_inference "$out_dir" --filter "^${iid}\$"; then
      echo "[smoke] inference failed for $iid, trying next"
      continue
    fi
    # msa cleans up its docker container in the background; wait it out
    # before starting eval so we never have two containers at once.
    wait_msa_clean

    pred_file="$out_dir/preds.json"
    if [[ ! -s "$pred_file" ]]; then
      echo "[smoke] no predictions produced for $iid, trying next"
      continue
    fi

    # step 2: evaluation
    if ! sb eval verified \
        --predictions "$pred_file" \
        --run-id "$sub_run" \
        --instance "$iid" \
        --workers "$MAX_WORKERS" \
        --report-dir "$WORKDIR/logs/run_evaluation"; then
      echo "[smoke] harness failed for $iid, trying next"
      continue
    fi

    # mini-swe-agent does NOT write a results.json — read resolved status from
    # the swebench harness per-instance report instead. The report lives at
    # $PROVIDER_DIR/logs/run_evaluation/... (swebench's RUN_EVALUATION_LOG_DIR
    # is a hardcoded relative path), NOT under $WORKDIR/logs/run_evaluation/.
    report="$PROVIDER_DIR/logs/run_evaluation/$sub_run/${LOG_MODEL_DIR}/$iid/report.json"
    if [[ -s "$report" ]] && py -c '
import json, sys
data = json.load(open(sys.argv[1]))
inst = data.get(sys.argv[2]) or next((v for v in data.values() if isinstance(v, dict)), {})
sys.exit(0 if inst.get("resolved") else 1)
' "$report" "$iid" 2>/dev/null; then
      new_ok=$((new_ok + 1))
      echo "[smoke] RESOLVED ✓ ($new_ok/$LIMIT_NEW_OK)"
    fi
    echo "[smoke] progress: resolved=$new_ok target=$LIMIT_NEW_OK attempts=$tries"
  done

  echo "[smoke] finished: $new_ok resolved out of $tries attempted"
  [[ "$new_ok" -ge "$LIMIT_NEW_OK" ]] && return 0 || return 1
}

# ---------------------------------------------------------------- full run
# Production pipeline: inference over all $MAX_INSTANCES instances, then
# evaluation, with live scoring printed in the background.
run_full() {
  cd "$WORKDIR"

  # step 1: multi-turn agent inference over SWE-bench Verified
  local out_dir="$WORKDIR/runs/$RUN_ID"
  local -a msa_args=(--output "$out_dir")
  if [[ -n "$MAX_INSTANCES" ]]; then
    local first_ids
    first_ids=$(head -n "$MAX_INSTANCES" <(
      py -c '
from datasets import load_dataset
ds = load_dataset("princeton-nlp/SWE-bench_Verified", split="test")
for i in ds["instance_id"]:
    print(i)
'
    ))
    msa_args+=(--filter "^(($(echo "$first_ids" | paste -sd '|' -)))\$")
  fi
  run_inference "$out_dir" "${msa_args[@]}"

  # step 2: evaluation
  local pred_file="$out_dir/preds.json"
  local -a eval_args=(verified --predictions "$pred_file" --run-id "$RUN_ID" \
                           --workers "$MAX_WORKERS" \
                           --report-dir "$WORKDIR/logs/run_evaluation")
  if [[ -n "$MAX_INSTANCES" ]]; then
    local iid
    for iid in $first_ids; do eval_args+=(--instance "$iid"); done
  fi

  # live score in background while evaluation runs
  "$PROVIDER_DIR/eval.sh" --live "$RUN_ID" &
  local live_pid=$!
  trap 'kill "$live_pid" 2>/dev/null || true' EXIT

  sb eval "${eval_args[@]}"

  wait "$live_pid" 2>/dev/null || true
  trap - EXIT

  echo "[done] final reports: $WORKDIR/logs/run_evaluation/$LOG_MODEL_DIR/$RUN_ID/"
  echo "[done] trajectories : $out_dir/"
}

# ---------------------------------------------------------------- dispatch
if [[ -n "$LIMIT_NEW_OK" ]]; then
  run_smoke
else
  run_full
fi