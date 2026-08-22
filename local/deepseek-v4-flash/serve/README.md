# local/deepseek-v4-flash/serve/

ds4-server를 띄우는 launcher와 CUDA watchdog. 이 디렉토리 안에서만 동작하며 다른 디렉토리와 아무것도 공유하지 않는다.

## 사용법

```bash
# 1. ds4-server 띄우기 (포어그라운드, watchdog 포함)
./serve.sh

# 2. 다른 셸에서 엔드포인트 확인
curl -s http://spark1.local:30000/v1/models | jq

# 3. 벤치마크 실행 (provider 디렉토리에서)
cd ../   # local/deepseek-v4-flash/
./run.sh -w 2
```

## 구성 변경

`serve.sh`는 tune27 구성 (ctx=512k / banks=3 / effort=max / DSpark ON / HBM OFF)을 그대로 보존한다. 다른 구성을 시도하려면:

```bash
cp serve.sh serve.tune30.sh
# flags 만 수정
```

## 환경변수

| 이름 | 기본값 | 설명 |
|---|---|---|
| `PORT` | `30000` | ds4-server listening port |
| `DS4_SERVER_BIN` | `$HOME/code/ds4/ds4-server` | ds4-server 바이너리 경로 |

## 파일

- `serve.sh` — tune27 구성으로 ds4-server 띄우기 (port 30000)
- `ds4-serve-with-watchdog.sh` — CUDA illegal memory access 감지 → 자동 재기동
- `logs/` — ds4-server stdout/stderr + watchdog 로그 (`.gitignore` 대상)
- 원본: `~/src/inference-engines/ds4-server/tune27-ds4-serve__ctx-512k__banks-3__effort-max.sh`