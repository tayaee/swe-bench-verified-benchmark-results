# openrouter.ai/stealth__ox-alpha/

## Responsibility split
The three top-level scripts map cleanly to the three pipeline stages:

| Script | Stage | What it does |
|---|---|---|
| `./run.sh`    | 1) inference | mini-swe-agent on SWE-bench Verified → `runs/<run_id>/preds.json` |
| `./eval.sh`   | 2) scoring   | `swebench eval` → per-instance `report.json` (idempotent) |
| `./report.sh` | 3) reporting | reads `report.json`, **auto-calls `./eval.sh` for missing items**, then prints score |

`./report.sh` makes "eval before report" the default — invoke it once and you always get a complete score (or a clear fallback message).

## Instruction
```bash
# 0) Smoke test
export OPENROUTER_API_KEY="sk-or-..."
./smoke-test.sh        # resolves a single pinned instance end-to-end
./clean.sh             # remove artifacts after smoke

# 1) Inference → 2) scoring → 3) report (one-shot)
./run.sh                                  # 500 instances, 4 workers
./eval.sh                                 # score everything in the run
./report.sh | tee results.txt             # show resolved/failed/unresolved

# Live monitoring while inference is still going (separate terminal)
./report.sh --live                        # every 30s: auto-eval unscored + reprint

# Just inspect what's there, without triggering new evals
./report.sh --no-eval

# Clean up
./clean.sh --docker                       # also purge leftover swebench containers
```
