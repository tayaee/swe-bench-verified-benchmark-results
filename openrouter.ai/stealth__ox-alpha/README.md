# openrouter.ai/stealth__ox-alpha/

stealth/ox-alpha via [OpenRouter](https://openrouter.ai). SWE-bench Verified 500 인스턴스 풀-벤치마크 대상.

이 디렉토리는 **self-contained**: 바깥 스크립트와 공유하지 않는다. 프로젝트 루트의 `pyproject.toml`/`uv.lock`(uv 의존성 manifest)만 참조한다.

## 사용법

```bash
export OPENROUTER_API_KEY="sk-or-..."

cd openrouter.ai/stealth__ox-alpha

./run.sh                  # 500 instances, 4 workers
./run.sh -w 8             # 더 병렬화
./run.sh --limit-new-ok 1 --limit-max-try 10   # smoke

./eval.sh                 # 최신 run 점수
./eval.sh --live          # 30초마다 polling
./eval.sh <run_id>        # 특정 run 점수
./eval.sh --all           # 전체 run 집계

./clean.sh                # swebench-work/ 삭제
./clean.sh --docker       # + 도커 컨테이너 / ~/.swebench 캐시 삭제

./smoke-test.sh           # Docker + API key + 1-instance 풀사이클
```

## 환경변수

| 이름 | 필수 | 설명 |
|---|---|---|
| `OPENROUTER_API_KEY` | ✅ | OpenRouter API 키 (`sk-or-v1-...`) |

## 파일

- `run.sh` — 추론 + 평가 파이프라인
- `eval.sh` — 점수 집계 / 실시간 polling
- `clean.sh` — 런타임 산출물 정리
- `smoke-test.sh` — provider 전용 preflight + 1-instance 풀사이클
- `msa.yaml` — mini-swe-agent 설정 override
- `provider.env` — 모델/auth 메타데이터
- `swebench-work/` — 런타임 산출물 (predictions, harness logs)