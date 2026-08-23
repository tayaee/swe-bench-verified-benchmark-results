# openrouter.ai/stealth__ox-alpha/

## Instruction
```bash
# 0) Smoke test
export OPENROUTER_API_KEY="sk-or-..."
./smoke-test.sh        # resolves a single pinned instance end-to-end
./clean.sh             # remove artifacts after smoke

# 1) Inference → 2) scoring → 3) report (one-shot)
./run.sh                                  # takes 1-2 days with 4 workers for 500 instances
./eval.sh                                 # score everything in the run
./report.sh | tee report.results.$(cat /etc/machine-id | cut -b1-8).txt

# Clean up
./clean.sh --docker                       # also purge leftover swebench containers
```

## SWE-bench Verified Result
* 2026-08-23 stealth/ox-alpha: 92.6% (report.results.7943e7d6.txt)

