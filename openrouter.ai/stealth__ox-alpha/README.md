# openrouter.ai/stealth__ox-alpha/

## Instruction

```bash
export OPENROUTER_API_KEY="sk-or-..."
cd openrouter.ai/stealth__ox-alpha

./smoke-test.sh
./clean.sh

./run.sh                  # 500 instances, 4 workers
./eval.sh
```

## Variable

| 이름 | 필수 | 설명 |
|---|---|---|
| `OPENROUTER_API_KEY` | ✅ | OpenRouter API 키 (`sk-or-v1-...`) |
