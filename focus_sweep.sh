#!/bin/sh
#
# Sweeps camera focus in each direction while logging focus position and
# FPGA stats at ~30Hz using rpoll.
#
# Usage: focus_sweep.sh [SPEED] [LEG_SECONDS] [POLL_T]

SPEED="${1:-20}"
LEG_SECONDS="${2:-2}"
POLL_T="${3:-0.0333}"
FIFO=/tmp/focus_sweep_stdin_fifo

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

sweep_leg() {
    direction=$1
    speed=$((direction * SPEED))
    log="/tmp/focus_sweep_rpoll_leg${direction}.txt"

    rm -f "$FIFO" "$log"
    mkfifo "$FIFO"
    exec 4<>"$FIFO"

    rpoll -f -t "$POLL_T" \
        .system.focus.position \
        .system.focus.stats.FPGAval1 \
        .system.focus.stats.FPGAval3 < "$FIFO" > "$log" &
    rpoll_pid=$!

    rlet system.focus.speed "$speed" > /dev/null
    sleep "$LEG_SECONDS"
    rlet system.focus.speed 0 > /dev/null

    kill -INT "$rpoll_pid" 2>/dev/null
    sleep 1
    if kill -0 "$rpoll_pid" 2>/dev/null; then
        kill -9 "$rpoll_pid" 2>/dev/null
    fi
    wait "$rpoll_pid" 2>/dev/null
    rpoll_pid=""

    exec 4>&-
    rm -f "$FIFO"

    cat "$log"
}

echo "Sweeping focus (speed=$SPEED, ${LEG_SECONDS}s per leg, poll=${POLL_T}s)..."
sweep_leg 1
sweep_leg -1
echo "Sweep complete"