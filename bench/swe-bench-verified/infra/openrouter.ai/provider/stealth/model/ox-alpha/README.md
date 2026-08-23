# stealth/ox-alpha (from openrouter.ai)

## SWE-bench Verified Result
* Leaderboard https://llm-stats.com/benchmarks/swe-bench-verified
* SWE-bench Verified Score [85.4%](benchmark.result.7943e7d6.txt) (Note: Two client-faults were retried, but made no change in the result.)

## Instruction
```bash
# smoke test
export OPENROUTER_API_KEY="sk-or-..."
./smoke-test.sh
./clean.sh

# inference (takes 1-2 days with 4 workers for 500 instances)
./run.sh
./eval.sh
./report.sh | tee benchmark.result.$(cat /etc/machine-id | cut -b1-8).txt

# clean up results and containers
./clean.sh --docker
```
