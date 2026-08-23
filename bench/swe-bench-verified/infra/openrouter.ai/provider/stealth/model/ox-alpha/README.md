# openrouter.ai/stealth__ox-alpha/

## Instruction
```bash
# smoke test
export OPENROUTER_API_KEY="sk-or-..."
./smoke-test.sh        # resolves a single pinned instance end-to-end
./clean.sh             # clean up results

# inference (takes 1-2 days with 4 workers for 500 instances)
./run.sh

# score
./eval.sh

# generate report
./report.sh | tee report.results.$(cat /etc/machine-id | cut -b1-8).txt

# clean up results and containers
./clean.sh --docker
```

## SWE-bench Verified Result
* 2026-08-23 stealth/ox-alpha: 92.6% (report.results.7943e7d6.txt)

