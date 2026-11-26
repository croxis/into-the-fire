#!/usr/bin/env bash
# Runs a dedicated server and a test player that joins it, picks a faction and
# launches, both headless, then fails if
#  - a step of the join is missing from either log (markers below), or
#  - either process exits early, or
#  - any error is logged that is not listed in the known-issues files.
#
# Unit tests run in one process, with no real connection. This is the test of
# the whole path over ENet: login handshake, interest, spawning on the client,
# snapshots, launch, and the pilot's input reaching the server.
#
# Usage: GODOT=/path/to/godot tests/smoke/join_smoke.sh
# Env:   GODOT (default: godot), JOIN_PORT (default: 2270, so a game on 2258 can keep running),
#        JOIN_TIMEOUT seconds to wait for all markers (default: 90),
#        JOIN_LINGER seconds to keep flying after the last marker (default: 5),
#        JOIN_LOGS directory for server.log and client.log (default: temp dir)
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
project="$(cd "$here/../.." && pwd)"
godot="${GODOT:-godot}"
port="${JOIN_PORT:-2270}"
deadline_s="${JOIN_TIMEOUT:-90}"
linger="${JOIN_LINGER:-5}"
logs="${JOIN_LOGS:-$(mktemp -d)}"
mkdir -p "$logs"
server_log="$logs/server.log"
client_log="$logs/client.log"
# shellcheck source=common.sh
. "$here/common.sh"

# Every step of a healthy join, in the order they happen.
server_markers=(
	"Server hosted on port"
	"Client Test Player authenticated"
	"Created pilot: Test Player in faction Zeta Wing"
	"Interest: peer"
	"Launching Test Player"
	"First input from Test Player applied"
	"Spawn complete for Test Player"
)
client_markers=(
	"Connection Succeded"
	"factions from server"
	"First snapshot for EASS Hyperion"
	"Asking to launch"
	"Ship Auora_Starfury faction"
)

server=""
client=""
cleanup() {
	for pid in $client $server; do
		kill "$pid" 2>/dev/null
	done
	wait 2>/dev/null
}
trap cleanup EXIT

# Prints the markers not yet in LOG. Usage: missing LOG MARKER...
missing() {
	local log="$1"
	shift
	for marker in "$@"; do
		grep -qF "$marker" "$log" || echo "$marker"
	done
}

alive() {
	kill -0 "$1" 2>/dev/null
}

echo "Join: server and test player on port $port (logs: $logs)"
"$godot" --headless --path "$project" --server --port="$port" >"$server_log" 2>&1 &
server=$!

# Start the client once the server is listening, however long the boot takes.
start=$SECONDS
until grep -qF "Server hosted on port" "$server_log"; do
	if ! alive "$server"; then
		echo "FAIL: server exited during boot"
		tail -n 50 "$server_log"
		exit 1
	fi
	if (( SECONDS - start > deadline_s )); then
		echo "FAIL: server not hosting after $deadline_s s"
		exit 1
	fi
	sleep 0.5
done
"$godot" --headless --path "$project" --testplayer --faction="Zeta Wing" --launch \
	--port="$port" >"$client_log" 2>&1 &
client=$!

failed=0
start=$SECONDS
while :; do
	todo="$(missing "$server_log" "${server_markers[@]}"; missing "$client_log" "${client_markers[@]}")"
	[ -z "$todo" ] && break
	for side in server client; do
		pid=${!side}
		if ! alive "$pid"; then
			echo "FAIL: $side exited before the join finished"
			failed=1
		fi
	done
	if [ "$failed" -ne 0 ] || (( SECONDS - start > deadline_s )); then
		[ "$failed" -eq 0 ] && echo "FAIL: join not finished after $deadline_s s"
		echo "Missing markers:"
		printf '%s\n' "$todo" | sed 's/^/  /'
		failed=1
		break
	fi
	sleep 0.5
done

if [ "$failed" -eq 0 ]; then
	echo "Join: done in $((SECONDS - start)) s; flying for $linger s more"
	sleep "$linger"
	for side in server client; do
		if ! alive "${!side}"; then
			echo "FAIL: $side exited after the join"
			failed=1
		fi
	done
fi
cleanup
trap - EXIT
strip_colours "$server_log"
strip_colours "$client_log"

errors="$(unexpected_errors "$server_log" "$here/known_issues.txt")"
if [ -n "$errors" ]; then
	echo "FAIL: unexpected server errors:"
	printf '%s\n' "$errors"
	failed=1
fi
errors="$(unexpected_errors "$client_log" "$here/known_issues.txt" "$here/known_client_issues.txt")"
if [ -n "$errors" ]; then
	echo "FAIL: unexpected client errors:"
	printf '%s\n' "$errors"
	failed=1
fi

if [ "$failed" -ne 0 ]; then
	echo "Join test failed. Logs: $logs"
	exit 1
fi
echo "Join: OK"
