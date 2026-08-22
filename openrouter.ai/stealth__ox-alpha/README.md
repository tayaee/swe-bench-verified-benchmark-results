# openrouter.ai/stealth__ox-alpha/

## Instruction
```bash
# Run smoke test
export OPENROUTER_API_KEY="sk-or-..."
./smoke-test.sh
./clean.sh

# Run the bench
./run.sh                  # 500 instances, 4 workers
./eval.sh | tee results.txt

# Clean up
./clean --docker
```
