# local-dgx-spark/deepseek-v4-flash/

## Instruction

```bash
# Run ds4-server on DGX Spark
./serve/serve.sh

# Run smoke test on WSL2
./smoke-test.sh
./clean.sh

# Run the bench on WSL2
./run.sh
./eval.sh | tee results.txt
./clean.sh --docker
```
