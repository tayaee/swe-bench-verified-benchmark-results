#!/bin/bash
# ============================================================================
# ds4-serve-with-watchdog.sh
#
# ds4-serve 를 띄우고 로그에서 "CUDA.*illegal memory access" 패턴을 감시한다.
# 이 패턴은 GPU 가 bad state 에 빠져 후속 요청이 모두 실패하는 catastrophic
# error 다. 검출 즉시 ds4-serve 를 kill 한 뒤 재기동한다 (최대 MAX_RESTARTS 회).
#
# 사용법:
#   ds4-serve-with-watchdog.sh <log_path> -- <ds4-serve flags...>
#
#   <log_path>: ds4-serve 의 stdout+stderr 가 캡쳐될 파일 경로
#               (watchdog 는 동일 이름 + ".watchdog.log" 에 자기 로그를 남긴다)
#
#   --: ds4-serve 플래그와 watchdog 인자를 구분
#
# 동작:
#   1. ds4-serve 를 백그라운드로 띄우고 PID 캡쳐
#   2. 5초마다 로그를 grep — "CUDA.*illegal memory access" 검출 시
#      kill -TERM (3s 대기) → kill -KILL (강제 종료)
#      → 다음 루프에서 ds4-serve 재기동
#   3. ds4-serve 가 0 으로 깨끗하게 종료되고 로그에 CUDA 패턴이 없으면
#      watchdog 도 0 으로 종료 (tmux 세션 종료)
#   4. ds4-serve 가 비정상 종료되면 (signal, non-zero exit) 항상 재기동
#
# 왜 exit 0 + CUDA 패턴이 *없는* 경우만 clean exit 인가:
#   사용자가 tmux 세션을 종료하면 ds4-serve 도 종료된다 (signal).
#   그건 정상 종료가 아니라 운영자 개입이다 — 재기동해서 무한 루프를
#   막기 위해 "0 exit 이고 CUDA 패턴 없을 때만" 종료한다.
#
# 원본: ~/src/inference-engines/ds4-server/ds4-serve-with-watchdog.sh
#       이 repo 로 가져오면서 변경 없음. ds4-serve 의 binary 위치는
#       DS4_SERVER_BIN 환경변수로 override 가능 (기본값: ~/code/ds4/ds4-server).
# ============================================================================

set -u

if [ "${1:-}" = "" ]; then
    echo "usage: $0 <log_path> -- <ds4-serve flags...>" >&2
    exit 64
fi

LOG="$1"
shift

# 첫 인자가 -- 가 아니면 에러
if [ "${1:-}" != "--" ]; then
    echo "usage: $0 <log_path> -- <ds4-serve flags...>" >&2
    echo "  (watchdog 인자 다음에 -- 구분자가 와야 합니다)" >&2
    exit 64
fi
shift  # consume the "--"

if [ $# -eq 0 ]; then
    echo "usage: $0 <log_path> -- <ds4-serve flags...>" >&2
    echo "  ds4-serve 플래그가 비어 있습니다" >&2
    exit 64
fi

WATCHDOG_LOG="${LOG%.log}.watchdog.log"
MAX_RESTARTS=10
restart=0

log_line() {
    printf '%s ds4-watchdog: %s\n' "$(date '+%m%d %H:%M:%S')" "$1" >> "$WATCHDOG_LOG"
}

: > "$LOG"
: > "$WATCHDOG_LOG"

DS4_SERVER_BIN="${DS4_SERVER_BIN:-$HOME/code/ds4/ds4-server}"

while [ "$restart" -lt "$MAX_RESTARTS" ]; do
    restart=$((restart + 1))
    log_line "starting ds4-serve (attempt $restart) — flags: $*"

    "$DS4_SERVER_BIN" "$@" > "$LOG" 2>&1 &
    PID=$!

    while kill -0 "$PID" 2>/dev/null; do
        sleep 5
        if grep -qE 'CUDA.*illegal memory access' "$LOG" 2>/dev/null; then
            log_line "CUDA illegal memory access detected — killing pid=$PID"
            kill -TERM "$PID" 2>/dev/null
            sleep 3
            kill -KILL "$PID" 2>/dev/null
            sleep 2
            break
        fi
    done

    wait "$PID" 2>/dev/null
    EXIT=$?
    log_line "ds4-serve exited (code=$EXIT, attempt=$restart)"

    # Clean exit (0) 이고 CUDA 패턴도 없으면 → watchdog 도 종료
    if [ "$EXIT" -eq 0 ] && ! grep -qE 'CUDA.*illegal memory access' "$LOG" 2>/dev/null; then
        log_line "clean exit — watchdog done"
        exit 0
    fi

    # 비정상 종료 (signal, non-zero exit, 또는 CUDA 검출) → 다음 루프에서 재기동
    log_line "non-clean exit — preparing restart"
    sleep 5
done

log_line "max restarts ($MAX_RESTARTS) reached — giving up"
exit 1