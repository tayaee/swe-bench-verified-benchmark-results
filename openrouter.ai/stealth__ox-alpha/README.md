# openrouter.ai/stealth__ox-alpha/

## Instruction
```bash
export OPENROUTER_API_KEY="sk-or-..."
./smoke-test.sh
./clean.sh
./run.sh                  # 500 instances, 4 workers
./eval.sh | tee results.txt
./clean --docker
```
