#!/bin/bash
# ============================================================================
# serve.sh — local-ds4-flash provider 의 서버 launcher (구성 27)
#
#   512k ctx / reasoning max / tokens 32768 / 뱅크 3개 / Fit 2048MB /
#   Graph 512MB / DSpark ON / HBM 캐시 OFF
#
# 포트: 30000 (OPENAI_API_BASE=http://spark1.local:30000/v1)
#       PORT 환경변수로 override 가능
#
# 다른 구성으로 바꾸려면 이 파일을 복사해서 flags 만 수정하면 된다.
# 원본: ~/src/inference-engines/ds4-server/tune27-ds4-serve__ctx-512k__banks-3__effort-max.sh
# ============================================================================
export PATH="$HOME/.local/bin:$HOME/bin:$PATH"

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SERVE_DIR="$ROOT/local/deepseek-v4-flash/serve"
LOG_DIR="$SERVE_DIR/logs"
mkdir -p "$LOG_DIR"

# HBM 캐시 OFF
export DS4_CUDA_NO_HBM_CACHE=1

# Q8 preload OFF
unset DS4_CUDA_Q8_F16_PRELOAD DS4_CUDA_Q8_F32_PRELOAD

# --- 뱅크 3개 & 헤드룸 (Fit 2048MB / Graph 512MB) ---
export DS4_SERVER_COALESCE_MAX=3
export DS4_SERVER_DEFAULT_TEMP=0
export DS4_BATCH_FIT_HEADROOM_MB=2048
export DS4_SESSION_GRAPH_HEADROOM_MB=512

# 부팅 시점에 session graph 를 pre-alloc (lazy 경로 제거)
export DS4_SESSION_LAZY_GRAPH=0

unset DS4_MODEL_ANON_HUGE

PORT="${PORT:-30000}"
LOG_FILE="$LOG_DIR/tmp.serve.log"

# ds4-serve wrapped in CUDA watchdog
exec "$SERVE_DIR/ds4-serve-with-watchdog.sh" \
    "$LOG_FILE" \
    -- \
    -c $((512 * 1024)) \
    --host 0.0.0.0 \
    --port "$PORT" \
    --tokens 32768 \
    --mem-floor-gb 1 \
    --reasoning-effort max