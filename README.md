# run-swebench-verified

SWE-bench Verified 500-instance benchmark runner with live scoring.

## stealth/ox-alpha (OpenRouter)

### Instruction
```bash
cd openrouter.ai/stealth__ox-alpha
export OPENROUTER_API_KEY="sk-or-..."

./smoke-test.sh      # 5-15 min, single-instance full cycle
./clean.sh           # remove reports only
./run.sh             # 500 instances, 4 workers
./eval.sh --live     # live scoring in another terminal
./clean.sh --docker  # final cleanup
```

### Results
TBD
