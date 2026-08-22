# run-swebench-verified

SWE-bench Verified 500 인스턴스 벤치마크를 **두 provider** 로 돌리고 점수를 실시간으로 확인하는 도구. 각 provider는 자기 디렉토리 안에서 **self-contained**로 동작한다 — 인접 provider 디렉토리와 아무것도 공유하지 않는다.

```
.
├── openrouter.ai/
│   └── stealth__ox-alpha/   ← stealth/ox-alpha (OpenRouter)
├── local/
│   └── deepseek-v4-flash/   ← DeepSeek-V4-Flash via ds4-server (OpenAI 호환)
├── pyproject.toml           ← 공유 의존성 manifest
├── uv.lock                  ← 공유 lock
├── main.py                  ← 무관 파일 (Hello World)
└── docs/
    └── quickstart.md        ← 처음 사람용 가이드
```

> 어떤 provider 디렉토리도 root의 다른 provider 디렉토리를 **읽지 않는다**. 두 provider는 독립적이다.

## Quickstart

```bash
# 1. 공통 의존성 설치 (uv가 .venv를 자동 생성)
uv sync

# 2. 벤치마크 돌릴 provider 디렉토리로 이동
cd openrouter.ai/stealth__ox-alpha
export OPENROUTER_API_KEY="sk-or-..."

./smoke-test.sh           # 5~15분, 1개 인스턴스 풀사이클
./run.sh                  # 500 instances, 4 workers (production)
./eval.sh --live          # 다른 터미널에서 실시간 점수
./clean.sh --docker       # 끝나면 청소
```

```bash
# ds4-server 기반 로컬 벤치
cd local/deepseek-v4-flash
./serve/serve.sh          # 별도 셸에서: ds4-server 띄우기
./smoke-test.sh           # ds4-server 도달성 + 1개 인스턴스 풀사이클
./run.sh                  # 500 instances, 2 workers
```

각 provider 디렉토리의 [`README.md`](openrouter.ai/stealth__ox-alpha/README.md) / [`README.md`](local/deepseek-v4-flash/README.md) 가 그 디렉토리의 사용법 / 환경변수 / 파일 구조를 자세히 설명한다.

## 스크립트 비교 (provider 공통 3 ops)

| op | OpenRouter | Local ds4-flash |
|---|---|---|
| run  | `./run.sh [-w N]` | `./run.sh [-w N]` (서버는 `./serve/serve.sh`로 별도 띄움) |
| eval | `./eval.sh [--live \| <run_id> \| --all]` | 동일 |
| clean| `./clean.sh [--docker]` | 동일 |

smoke-test는 provider마다 다름 (OpenRouter는 Docker/API key, ds4-flash는 추가로 `/v1/models` 도달성).

## 공통 요구사항

- `uv` ([astral.sh/uv](https://docs.astral.sh/uv/)) — `uv sync`로 `.venv/` 자동 셋업
- Docker daemon (swebench harness가 인스턴스당 컨테이너 빌드)
- x86_64 호스트 (swebench Docker 이미지가 arm64 미지원)

## 디렉토리 규칙

각 provider 디렉토리는 다음을 만족한다:

1. **인접 provider 디렉토리와 공유하지 않음**: `source ../...` / `source ../../lib/...` 같은 호출 없음
3. **root의 `pyproject.toml`만 참조**: uv-managed 의존성 manifest 공유 (스크립트가 아님)
4. **자기 swebench-work 보유**: 런타임 산출물도 디렉토리 안에 격리
5. **자체 smoke-test 보유**: provider별 preflight 다름

## 역사

- [`handoff.md`](handoff.md): aarch64 → x86_64 마이그레이션 + multi-turn agent 전환 기록
- [`swebench-verified.quickstart.md`](swebench-verified.quickstart.md): 처음 사람용 빠른 시작