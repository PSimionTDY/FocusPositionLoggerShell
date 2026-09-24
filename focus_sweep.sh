#!/bin/sh
#
# Homes camera focus to near focus (position 0), then performs a single
# sweep to far focus (position 65535) while logging focus position and
# FPGA stats at ~30Hz using rpoll.
#
# Usage: focus_sweep.sh [SPEED] [POLL_T] [MOVE_TIMEOUT]

SPEED="${1:-20}"
POLL_T="${2:-0.0333}"
MOVE_TIMEOUT="${3:-30}"
FIFO=/tmp/focus_sweep_stdin_fifo
LOG=/tmp/focus_sweep_rpoll.txt

MIN_POS=0
MAX_POS=65535
STALL_POLLS=5
STALL_POLL_T=0.2

cleanup() {
    rlet system.focus.speed 0 > /dev/null 2>&1

    if [ -n "$rpoll_pid" ]; then
        kill -INT "$rpoll_pid" 2>/dev/null
        sleep 1
        if kill -0 "$rpoll_pid" 2>/dev/null; then
            kill -9 "$rpoll_pid" 2>/dev/null
        fi
        wait "$rpoll_pid" 2>/dev/null
    fi

    exec 4>&- 2>/dev/null
    rm -f "$FIFO"
}

trap cleanup EXIT INT TERM

get_position() {
    rpoll .system.focus.position
}

# Drives focus at direction*SPEED until position stops changing (i.e. the
# mechanical end stop has been reached) or MOVE_TIMEOUT (seconds) elapses.
move_to_limit() {
    direction=$1
    speed=$((direction * SPEED))

    rlet system.focus.speed "$speed" > /dev/null

    max_polls=$((MOVE_TIMEOUT * 5))
    poll_count=0
    stall_count=0
    last_pos=$(get_position)

    while [ "$poll_count" -lt "$max_polls" ]; do
        sleep "$STALL_POLL_T"
        poll_count=$((poll_count + 1))

        pos=$(get_position)
        if [ "$pos" = "$last_pos" ]; then
            stall_count=$((stall_count + 1))
            if [ "$stall_count" -ge "$STALL_POLLS" ]; then
                break
            fi
        else
            stall_count=0
        fi
        last_pos=$pos
    done

    rlet system.focus.speed 0 > /dev/null
}

echo "Homing focus to near limit (position ~$MIN_POS)..."
move_to_limit -1

rm -f "$FIFO" "$LOG"
mkfifo "$FIFO"
exec 4<>"$FIFO"

rpoll -f -t "$POLL_T" \
    .system.focus.position \
    .system.focus.stats.FPGAval1 \
    .system.focus.stats.FPGAval3 < "$FIFO" > "$LOG" &
rpoll_pid=$!

echo "Sweeping focus to far limit (position ~$MAX_POS), speed=$SPEED, poll=${POLL_T}s..."
move_to_limit 1

kill -INT "$rpoll_pid" 2>/dev/null
sleep 1
if kill -0 "$rpoll_pid" 2>/dev/null; then
    kill -9 "$rpoll_pid" 2>/dev/null
fi
wait "$rpoll_pid" 2>/dev/null
rpoll_pid=""

exec 4>&-
rm -f "$FIFO"

cat "$LOG"
echo "Sweep complete"