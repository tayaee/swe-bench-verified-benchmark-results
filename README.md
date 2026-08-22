# ox-alpha-swebench-verified

Run the **ox-alpha** model ([openrouter.ai](https://openrouter.ai)) on
**SWE-bench Verified** and score it live.

- Model id: `stealth/ox-alpha` on openrouter.ai, requires the `OPENROUTER_API_KEY` environment variable
- Environment managed by [uv](https://docs.astral.sh/uv/) (`pyproject.toml` + `uv.lock`)
- Evaluation harness: [swebench](https://github.com/SWE-bench/SWE-bench) (Docker required)

## Quickstart

```bash
# 1. Install dependencies (creates .venv via uv)
uv sync

# 2. Smoke test — try instances until 1 succeeds (max 10 new attempts)
./smoke-test.sh

# 3. Full run over SWE-bench Verified
./run-swebench-verified.sh

# Live score while running (in another terminal)
./eval.sh --all
```

## Scripts

| Script | Purpose |
|---|---|
| `run-swebench-verified.sh` | Run inference + evaluation over SWE-bench Verified |
| `eval.sh` | Score finished instances; prints resolution rate in real time |
| `smoke-test.sh` | End-to-end smoke test: Docker check → 1-resolve run → score check |

## Usage

```bash
./run-swebench-verified.sh                 # all 500 instances, 4 workers
./run-swebench-verified.sh -w 8            # 8 parallel workers
./run-swebench-verified.sh --limit-new-ok 1 --limit-max-try 10
                                           # smoke mode: stop after 1 resolve,
                                           # at most 10 new attempts
```

### eval.sh modes

```bash
./eval.sh                # newest run only
./eval.sh <run_id>       # specific run
./eval.sh --all          # aggregate every run under logs/
./eval.sh --live <id>    # keep polling every 30 s (used automatically by the runner)
```

## Requirements

- `uv` (https://docs.astral.sh/uv/)
- Docker daemon running (the swebench harness builds/pulls per-instance containers)
- `OPENROUTER_API_KEY` environment variable
