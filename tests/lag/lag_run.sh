#!/usr/bin/env bash
# Runs a dedicated server and a test player joined through lag_proxy.py, then
# prints the netcode reports: the server's "Input from" lines and the client's
# "Prediction for" lines (which appear only when there were corrections).
#
#   GODOT=/path/to/custom/godot tests/lag/lag_run.sh [LATENCY_MS] [JITTER_MS] [LOSS_PERCENT] [SECONDS] [TEST PLAYER FLAGS...]
#
# LATENCY_MS is one way, so ping is twice it. Defaults: 50 ms, no jitter or loss, 60 s.
# Needs ports 2258 (server) and 2259 (proxy) free. Logs stay in a temporary folder.
set -u
: "${GODOT:?set GODOT to the custom engine binary}"
latency=${1:-50} jitter=${2:-0} loss=${3:-0} seconds=${4:-60}
cd "$(dirname "$0")/../.."
logs=$(mktemp -d)

python3 tests/lag/lag_proxy.py 2259 2258 "$latency" "$jitter" "$loss" &
proxy=$!
trap 'kill $proxy 2>/dev/null' EXIT
timeout $((seconds + 5)) "$GODOT" --headless --path . --server > "$logs/server.log" 2>&1 &
server=$!
sleep 3
timeout "$seconds" "$GODOT" --headless --path . --testplayer --faction="Zeta Wing" --launch \
	--port=2259 "${@:5}" > "$logs/client.log" 2>&1
wait $server

strip() { sed 's/\x1b\[[0-9;]*m//g'; }
echo "Latency $latency ms one way, jitter ±$jitter ms, loss $loss% ($seconds s). Logs: $logs"
echo "Server, every 5 s:"
grep -h "Input from" "$logs/server.log" | strip | sed 's/^.*Input from /  /'
echo "Client, 5 s spells with corrections:"
grep -h "Prediction for" "$logs/client.log" | strip | sed 's/^.*Prediction for /  /'
echo "Errors (headless client's options-menu errors left out):"
grep -h "ERROR" "$logs/server.log" "$logs/client.log" | grep -v "display server" | sort | uniq -c
