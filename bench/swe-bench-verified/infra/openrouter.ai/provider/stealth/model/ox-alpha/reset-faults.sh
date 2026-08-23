#!/usr/bin/env bash
# reset-faults.sh — Reset pending fault instances so ./run.sh retries them.
#
# Companion to report.sh's "others" breakdown. Finds predictions that have no
# eval report yet ("others"), classifies them by fault owner from their
# .traj.json exit status (same mapping as report.sh), and — for the requested
# category only — deletes:
#   1. runs/<run_id>/<instance_id>/            (.traj.json; msa skips if present)
#   2. runs/<run_id>/preds.json entry          (harness treats as submitted)
# leaving everything else untouched. Afterwards re-run:
#   ./run.sh        # re-runs inference for the reset instances
#   ./report.sh     # scores them and updates the breakdown
#
# Usage:
#   ./reset-faults.sh <infra-faults|engine-faults|model-faults|client-faults> [run_id]
#   ./reset-faults.sh client-faults --yes      # skip confirmation prompt
#   RUN_ID=run-1 ./reset-faults.sh infra-faults

set -euo pipefail

PROVIDER_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$PROVIDER_DIR/../.." && pwd)"
WORKDIR="$PROVIDER_DIR/swebench-work"

# shellcheck source=provider.env
source "$PROVIDER_DIR/provider.env"

CATEGORY=""
RUN_ID="${RUN_ID:-run-1}"
ASSUME_YES=false
for arg in "$@"; do
  case "$arg" in
    infra-faults|engine-faults|model-faults|client-faults) CATEGORY="$arg" ;;
    --yes|-y) ASSUME_YES=true ;;
    --help|-h)
      sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) RUN_ID="$arg" ;;
  esac
done

if [[ -z "$CATEGORY" ]]; then
  echo "error: missing category (infra-faults|engine-faults|model-faults|client-faults)" >&2
  exit 1
fi

py() { uv run --project "$REPO_ROOT" python "$@"; }

PRED_FILE="$WORKDIR/runs/$RUN_ID/preds.json"
if [[ ! -f "$PRED_FILE" ]]; then
  echo "error: no preds.json at $PRED_FILE (run '$RUN_ID' not found)" >&2
  exit 1
fi

# ---------------------------------------------------------------- select
# Classify every prediction without a report.json (same logic as report.sh)
# and keep only the ones belonging to $CATEGORY. Writes selected ids to a
# temp file so the apply step below can't drift from this selection.
SELECTED="$(mktemp)"
trap 'rm -f "$SELECTED"' EXIT

LOG_BASE="$WORKDIR/logs/run_evaluation"
py - "$PRED_FILE" "$WORKDIR" "$RUN_ID" "$LOG_BASE" "$PROVIDER_ID" "$CATEGORY" \
   "$LOG_MODEL_DIR" "$SELECTED" <<'EOF'
import json, os, sys

pred_file, workdir, run_id, log_base, provider_id, category, log_model_dir, out = sys.argv[1:9]

# Must stay in sync with report.sh / STATUS_TO_FAULT there.
STATUS_TO_FAULT = {
    "OpenRouterRateLimitError": "infra-faults",
    # engine-faults intentionally empty — add harness-side statuses here as
    # they are observed (e.g. some eval crash signature).
    "RepeatedFormatError":      "model-faults",
    "KeyError":                 "model-faults",
    "LimitsExceeded":           "model-faults",
    "no-traj":                  "client-faults",
}

preds = json.load(open(pred_file))
ids = list(preds.keys()) if isinstance(preds, dict) else [p["instance_id"] for p in preds]

selected = []
for iid in ids:
    report = os.path.join(log_base, run_id, log_model_dir, iid, "report.json")
    if os.path.exists(report):
        continue  # already scored — not "others"
    traj = os.path.join(workdir, "runs", str(run_id), iid, f"{iid}.traj.json")
    try:
        status = json.load(open(traj)).get("info", {}).get("exit_status") or "no-traj"
    except Exception:
        status = "no-traj"
    cat = STATUS_TO_FAULT.get(status)
    if cat == category:
        selected.append((iid, status))

with open(out, "w") as f:
    for iid, _ in selected:
        f.write(iid + "\n")

print(f"[reset] run={run_id} category={category}: {len(selected)} instance(s) to reset")
for iid, status in selected:
    print(f"[reset]   {iid}  ({status})")
EOF

n=$(wc -l < "$SELECTED" | tr -d ' ')
if [[ "$n" -eq 0 ]]; then
  echo "[reset] nothing to reset"
  exit 0
fi

if ! $ASSUME_YES; then
  printf "%s" "[reset] delete trajectories + preds entries for these $n instance(s)? [y/N] "
  IFS= read -r reply
  [[ "$reply" == "y" || "$reply" == "Y" ]] || { echo "[reset] aborted"; exit 1; }
fi

# ---------------------------------------------------------------- apply
backup="$PRED_FILE.bak.$(date +%Y%m%d-%H%M%S)"
cp "$PRED_FILE" "$backup"
echo "[reset] backed up preds.json -> $(basename "$backup")"

while IFS= read -r iid; do
  traj_dir="$WORKDIR/runs/$RUN_ID/$iid"
  if [[ -d "$traj_dir" ]]; then
    rm -rf "$traj_dir"
    echo "[reset] removed $traj_dir"
  fi
done < "$SELECTED"

py - "$PRED_FILE" "$SELECTED" <<'EOF'
import json, os, sys
pred_file, selected = sys.argv[1], sys.argv[2]
with open(selected) as f:
    drop = {line.strip() for line in f if line.strip()}
preds = json.load(open(pred_file))
removed = [iid for iid in drop if preds.pop(iid, None) is not None]
json.dump(preds, open(pred_file, "w"), indent=2)
print(f"[reset] removed {len(removed)} entr(ies) from {os.path.basename(pred_file)}")
EOF

echo "[reset] done — now run './run.sh' to retry, then './report.sh' to rescore"
