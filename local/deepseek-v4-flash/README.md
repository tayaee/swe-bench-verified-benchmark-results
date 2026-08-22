# local/deepseek-v4-flash/

DeepSeek-V4-Flash via [ds4-server](https://github.com/eugr/ds4-server) (OpenAI 호환). 로컬 LAN에서 실행 중인 ds4-server 엔드포인트를 통해 SWE-bench Verified를 돌리고 평가한다.

이 디렉토리는 **self-contained**: 바깥 스크립트와 공유하지 않는다. 프로젝트 루트의 `pyproject.toml`/`uv.lock`(uv 의존성 manifest)만 참조한다.

## 사용법

```bash
# 1. ds4-server 띄우기 (별도 셸 / tmux)
./serve/serve.sh

# 2. 벤치마크 (이 디렉토리에서)
cd local/deepseek-v4-flash
./run.sh                  # 500 instances, 2 workers (local LLM 기본값)
./run.sh -w 4             # 더 병렬화 (서버 capacity 확인 후)
./run.sh --limit-new-ok 1 --limit-max-try 5   # smoke

# 3. 평가/리포트
./eval.sh                 # 최신 run 점수
./eval.sh --live          # 30초마다 polling
./eval.sh <run_id>        # 특정 run 점수
./eval.sh --all           # 전체 run 집계

# 4. 청소
./clean.sh                # swebench-work/ 삭제
./clean.sh --docker       # + 도커 컨테이너 / ~/.swebench 캐시 삭제

# 5. Smoke test
./smoke-test.sh           # Docker + ds4-server 도달성 + 1-instance 풀사이클
```

## 환경변수

| 이름 | 기본값 | 설명 |
|---|---|---|
| `OPENAI_API_BASE` | `http://spark1.local:30000/v1` | ds4-server 엔드포인트 |
| `OPENAI_API_KEY` | `none` | ds4-server가 받는 dummy key |

둘 다 셸에서 export하면 provider 디폴트 override.

## 파일

- `run.sh` — 추론 + 평가 파이프라인
- `eval.sh` — 점수 집계 / 실시간 polling
- `clean.sh` — 런타임 산출물 정리
- `smoke-test.sh` — provider 전용 preflight + 1-instance 풀사이클
- `msa.yaml` — mini-swe-agent 설정 override
- `provider.env` — 모델/엔드포인트/auth 메타데이터
- `serve/serve.sh` — ds4-server launcher (tune27 구성)
- `serve/ds4-serve-with-watchdog.sh` — CUDA illegal memory access watchdog
- `swebench-work/` — 런타임 산출물 (predictions, harness logs)

## ds4-server 운영

```bash
# ds4-server 실행 (포어그라운드, watchdog 포함)
./serve/serve.sh

# 다른 셸에서 모델 목록 확인
curl -s "$OPENAI_API_BASE/models" | jq

# 종료
# tmux 세션 detach/detach 후: Ctrl-C in tmux
```