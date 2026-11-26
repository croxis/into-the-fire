#!/usr/bin/env bash
# Boots the dedicated server headless for a fixed number of frames and fails if
#  - the expected startup markers are missing, or
#  - any engine/script error is logged that is not listed in known_issues.txt.
#
# Usage: GODOT=/path/to/godot tests/smoke/server_smoke.sh
# Env:   GODOT (default: godot), SMOKE_FRAMES (default: 1800), SMOKE_LOG (default: temp file)
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
project="$(cd "$here/../.." && pwd)"
godot="${GODOT:-godot}"
frames="${SMOKE_FRAMES:-1800}"
log="${SMOKE_LOG:-$(mktemp)}"
known="$here/known_issues.txt"
# shellcheck source=common.sh
. "$here/common.sh"

echo "Smoke: booting dedicated server for $frames frames (log: $log)"
timeout 600 "$godot" --headless --path "$project" --quit-after "$frames" --server >"$log" 2>&1
status=$?
if [ "$status" -ne 0 ]; then
	echo "FAIL: Godot exited with status $status"
	tail -n 50 "$log"
	exit 1
fi

failed=0

# Things that must happen during a healthy boot.
for marker in "Server hosted on port" "Galaxy setup complete" "Added station" "Added ship EASS Hyperion"; do
	if ! grep -qF "$marker" "$log"; then
		echo "FAIL: missing startup marker: $marker"
		failed=1
	fi
done

# Every error line, minus the known ones.
errors="$(unexpected_errors "$log" "$known")"
if [ -n "$errors" ]; then
	echo "FAIL: unexpected errors:"
	printf '%s\n' "$errors"
	failed=1
fi

if [ "$failed" -ne 0 ]; then
	echo "Smoke test failed. Full log: $log"
	exit 1
fi
echo "Smoke: OK"
