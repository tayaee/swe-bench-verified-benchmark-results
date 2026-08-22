# swebench-verified.quickstart.md — 처음 돌리는 사람용 가이드

이 저장소는 **ox-alpha** 모델(`openrouter.ai`)을 **SWE-bench Verified** 500개 인스턴스에 대해 돌리고 점수를 실시간으로 확인하는 도구예요.

## 0. 준비물

| 항목 | 확인 방법 |
|---|---|
| Docker daemon 실행 중 | `docker info` 가 에러 없이 끝남 |
| [`uv`](https://docs.astral.sh/uv/) 설치됨 | `uv --version` |
| OpenRouter API 키 | `export OPENROUTER_API_KEY=sk-or-...` |

## 1. 설치 (venv 자동 생성)

```bash
uv sync
```

> `uv sync` 한 번이면 끝. 의존성(`swebench[all]`, `litellm`, `datasets`)은 `pyproject.toml`에 모두 선언되어 있고, `.venv/`에 자동 설치됩니다.

## 2. 스모크 테스트 (가장 먼저 — 5분)

추론 → 도커 빌드 → 평가까지 파이프라인이 살아있는지 1개 인스턴스로 확인:

```bash
./smoke-test.sh
```

끝에 `[smoke-test] ALL CHECKS PASSED` 가 나오면 OK. 안 나오면 위 준비물 / Docker 권한부터 점검.

## 3. 벤치 돌리기 (1줄)

```bash
./run-swebench-verified.sh
```

기본값 = 500개 인스턴스 전부, 4 workers. 끝나면 `swebench-work/logs/run_evaluation/<run_id>/` 아래에 인스턴스별 리포트가 쌓입니다.

다른 옵션:

```bash
./run-swebench-verified.sh -w 8                  # 8 workers
./run-swebench-verified.sh 50                    # 처음 50개만
./run-swebench-verified.sh --limit-new-ok 3 --limit-max-try 20
                                            # 3개 풀릴 때까지 시도 (최대 20번)
```

## 4. 점수 보기

### 벤치 돌리는 동안 실시간으로 (1줄, 다른 터미널에서)

```bash
./eval.sh --live
```

30초마다 누적된 resolution rate을 다시 계산해서 출력. 벤치 프로세스가 끝나면 같이 종료.

### 다 끝나고 나서 (1줄)

```bash
./eval.sh                         # 가장 최근 run
./eval.sh ox-alpha-20260821-235216 # 특정 run
./eval.sh --all                   # 모든 run 합산
```

출력 예:

```
=== SWE-bench Verified LIVE SCORE — run: ox-alpha-20260821-235216 ===
  completed : 437
  resolved  :  87 (19.9%)
  failed    : 312 (71.4%)
  unresolved:  38 ( 8.7%)
  >>> resolution rate: 19.9% <<<
```

## 5. 끝. 자주 하는 질문

**Q. `python -m swebench.harness.run_evaluation ...` 과 `swebench eval verified ...` 차이?**
A. 같은 `main()` 함수를 부르는 두 형태. 공식 권장은 후자(이게 v5.x부터의 표준 CLI). README: *"The previous `python -m swebench.harness.run_evaluation ...` form still works and takes the same arguments as before."*

**Q. 결과는 어디에?**
A. `swebench-work/logs/run_evaluation/<run_id>/<model>__/<instance_id>/report.json` 와 `test_output.txt`. `./eval.sh`가 자동으로 긁어모음.

**Q. 점수 재계산만 하고 싶어요 (도커 안 띄우고)**
```bash
uv run --project . swebench report <run_id>
```
이미 저장된 `test_output.txt`로부터 verdict만 다시 매김. 로그 파서 고친 직후에 유용.

**Q. 어디서 더 봐요?**
- 상세 사용법: [`README.md`](README.md)
- 평가 헬퍼: [`eval.sh`](eval.sh)
- 스모크 테스트: [`smoke-test.sh`](smoke-test.sh)
