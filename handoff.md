# handoff.md — SWE-bench Verified / ox-alpha pipeline handoff

This folder was migrated to the **multi-turn agent** approach on an aarch64 machine, but the Docker images SWE-bench publishes are **x86_64-only**, so end-to-end smoke-test could not be run here. The actual evaluation must be performed on an x86_64 host.

This document is the handoff package: it captures every code change, why it was made, what to verify on the new host, and known caveats.

---

## TL;DR for the receiver

```bash
# 1. clone (or rsync) this folder onto an x86_64 host
cd /path/to/ox-alpha-swebench-verified
uv sync                                  # installs mini-swe-agent, swebench, litellm
export OPENROUTER_API_KEY=sk-or-...

# 2. sanity check
./smoke-test.sh                          # ~5–15 min; expect "[smoke-test] ALL CHECKS PASSED"

# 3. full run over SWE-bench Verified
./run-swebench-verified.sh -w 4          # ~hours; 500 instances

# 4. live score in another terminal
./eval.sh --live
```

If `./smoke-test.sh` does not print `ALL CHECKS PASSED`, read the "Known issues" section below.

---

## Code changes shipped

### 1. `run-swebench-verified.sh` — full rewrite of the inference + eval pipeline

**Before:** two-step pipeline using a custom single-turn `predict.py` and the legacy harness module entry point.

**After:** single multi-turn agent run, then official harness evaluation.

| Phase | Old | New |
| --- | --- | --- |
| Inference | `python predict.py` (single-turn, litellm direct call) | `python -m minisweagent.run.benchmarks.swebench` (multi-turn agent in Docker, ~15–50 turns/instance) |
| Eval | `python -m swebench.harness.run_evaluation ...` (legacy module form) | `swebench eval verified ...` (Typer CLI, the standard form per SWE-bench v5+) |

Key arguments now used:

```bash
python -m minisweagent.run.benchmarks.swebench \
  --subset verified \
  --split test \
  --model stealth/ox-alpha \
  --model-class minisweagent.models.openrouter_model.OpenRouterModel \
  -c swebench.yaml \
  --output <out_dir> \
  --workers N \
  --filter '^instance_id$'   # or no --filter for full run
```

```bash
swebench eval verified \
  --predictions <out_dir>/preds.json \
  --run-id <id> \
  --workers N \
  --report-dir swebench-work/logs/run_evaluation
  [--instance <id> ...]      # only when limiting to a subset
```

### 2. `swebench.yaml` (new file) — mini-swe-agent config for OpenRouter

Only overrides the bits we need; everything else falls back to the package default at
`.venv/lib/python3.13/site-packages/minisweagent/config/benchmarks/swebench.yaml` (agent system/instance templates, Docker env, observation template).

```yaml
agent:
  step_limit: 250       # max model turns per instance
  cost_limit: 3.0       # USD cap per instance

environment:
  timeout: 60           # shell command timeout (s)

model:
  model_name: "stealth/ox-alpha"
  model_kwargs:
    drop_params: true   # drop unsupported litellm params instead of erroring
  cost_tracking: "ignore_errors"  # ox-alpha not in cost tables; suppress errors
```

**Why `-c swebench.yaml` matters:** mini-swe-agent's `--config` REPLACES the default config unless you explicitly include the default file path. By keeping our overrides minimal, the merge with the default swebench.yaml happens automatically.

### 3. `pyproject.toml` — added `mini-swe-agent` dependency

```diff
 dependencies = [
     "swebench[all]",
     "litellm",
     "datasets",
+    "mini-swe-agent",
 ]
```

`uv sync` pulls it (and its transitive deps: `prompt-toolkit`, `textual`, etc.).

### 4. `predict.py` — preserved but only used as fallback

If you ever need single-turn baseline (e.g. comparing cost/latency), `predict.py` was patched:

```python
litellm_model = (
    args.model
    if "/" in args.model.split("/")[0] or args.model.startswith(("openai/", "anthropic/", "azure/"))
    else f"openrouter/{args.model}"
)
```

OpenRouter models need the `openrouter/` provider prefix for litellm to know which API to call. litellm rejects bare ids like `stealth/ox-alpha` with `BadRequestError: LLM Provider NOT provided`. The default `run-swebench-verified.sh` no longer uses `predict.py`, but the fix is in if you re-enable it.

### 5. `eval.sh` — paths now match the new CLI's output layout

The new `swebench eval` writes per-instance logs under `swebench-work/logs/run_evaluation/<run_id>/<model>__/<instance_id>/report.json` (with `RUN_EVALUATION_LOG_DIR = Path("logs/run_evaluation")`). `eval.sh` still expects that layout; no changes needed once `--report-dir` is pinned in `run-swebench-verified.sh`.

---

## What to verify on the new host

### Smoke test (~5–15 min)

```bash
./smoke-test.sh
```

Expect:
1. `[1/3] Docker check` PASS
2. `[2/3]` runs `run-swebench-verified.sh -w 1 --limit-new-ok 1 --limit-max-try 10` and stops as soon as 1 instance resolves (or after 10 attempts)
3. `[3/3]` runs `./eval.sh --all` and finds `resolved: 1+` in the output
4. Final line: `[smoke-test] ALL CHECKS PASSED`

If you see `litellm.BadRequestError: LLM Provider NOT provided`, model id was passed without the OpenRouter prefix — this means the inference path is bypassing `swebench.yaml`. Check that `--model-class minisweagent.models.openrouter_model.OpenRouterModel` is present in the script.

### Pipeline correctness (without full run)

```bash
# Check minisweagent CLI parses args and finds the instance
uv run --project . python -m minisweagent.run.benchmarks.swebench \
  --subset verified --split test \
  --model stealth/ox-alpha \
  --model-class minisweagent.models.openrouter_model.OpenRouterModel \
  -c swebench.yaml \
  --output /tmp/check-msa --workers 1 \
  --filter '^astropy__astropy-12907$' 2>&1 | tail -10
# Expected: "Instance filter: 500 -> 1 instances" and a docker run for the instance
```

### Liveness check (no real benchmark)

```bash
# swebench CLI works
uv run --project . swebench eval --help | head -5

# minisweagent loads our config
uv run --project . python -m minisweagent.run.benchmarks.swebench --help 2>&1 | grep -i "model_class\|model-class" | head -3
```

---

## Known issues / caveats

### 1. Architecture (the reason for this handoff)

- This folder was prepared on **aarch64**. SWE-bench publishes **x86_64-only** Docker images (`swebench/sweb.eval.x86_64.<repo>_<instance>`). On aarch64, image pull fails with `no matching manifest for linux/arm64/v8`.
- QEMU user-mode emulation was not installed; installing it would work but adds 5–20× slowdown, which makes 500-instance runs impractical.
- **The receiving host MUST be x86_64.** Confirm before smoke test:
  ```bash
  uname -m   # expect: x86_64
  ```

### 2. `mini-swe-agent` package name

The package on PyPI is **`mini-swe-agent`** (with hyphens), not `minisweagent`. `pyproject.toml` has the correct name.

### 3. Default config replacement

`mini-sweagent.run.benchmarks.swebench --config X.yaml` REPLACES the default config unless you pass the default file path explicitly. Our `swebench.yaml` only overrides what we need (model + cost), so agent templates stay default. If you customize further, copy fields from
`.venv/lib/python3.13/site-packages/minisweagent/config/benchmarks/swebench.yaml`.

### 4. ox-alpha pricing not in OpenRouterModel cost tables

`cost_tracking: "ignore_errors"` in `swebench.yaml` is required; otherwise the agent loop will refuse to start with "missing cost info." Real $ usage is not auto-tracked.

### 5. Trajectory logs can be large

Each run instance stores the full conversation in `<out_dir>/<instance_id>/trajectory.json` (or similar). 500 instances × 50 turns × multi-KB per turn = a few GB. Clean up old runs with `rm -rf swebench-work/runs/*` between iterations.

### 6. `OPENROUTER_API_KEY`

The script `set -euo pipefail`'s and will refuse to run without this env var. Set it before invoking any script:
```bash
export OPENROUTER_API_KEY=sk-or-v1-...
```

---

## File map

```
ox-alpha-swebench-verified/
├── pyproject.toml          # +mini-swe-agent
├── swebench.yaml           # NEW — mini-swe-agent OpenRouter config
├── run-swebench-verified.sh # rewrite: minisweagent (inference) + swebench eval
├── predict.py              # patched (openrouter/ prefix); unused by default
├── eval.sh                 # unchanged; consumes swebench eval output layout
├── smoke-test.sh           # unchanged; wraps run-swebench-verified.sh
├── README.md               # unchanged (will need refresh if you want)
└── swebench-verified.quickstart.md  # NEW; first-runner guide
```

---

## Open follow-ups (not blocking, but worth noting)

- `README.md` still references the old `predict.py` flow. Worth refreshing to point at `mini-swe-agent`.
- The `predict.py` fallback path is patched but no longer exercised by `run-swebench-verified.sh`. Consider deleting or moving to a separate `tools/` dir.
- `eval.sh` reads `<model>__/<instance_id>/report.json`. If the layout changes in a future swebench release, only `eval.sh` needs updating.
- For very large runs, consider sharding with `--slice 0:100`, `--slice 100:200`, ... and a separate aggregation step. mini-swe-agent supports this natively.
