# SWE-bench Verified (local test results)

SWE-bench Verified 500-instance benchmark runner with live scoring.

## stealth/ox-alpha (served by openrouter.ai)

### Instruction
```bash
export OPENROUTER_API_KEY="sk-or-..."
cd openrouter.ai/stealth__ox-alpha
./smoke-test.sh      # solve 1 question to check the pipeline
./clean.sh           # remove all reports
./run.sh             # inference
./eval.sh            # scoring in another terminal
./report.sh          # reporting
./clean.sh --docker  # remove all reports and docker containers
```
