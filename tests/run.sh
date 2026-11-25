#!/usr/bin/env bash
# Runs the GUT unit tests and prints a short report: one line when everything
# passes; otherwise each failing test's own output (errors, backtraces, logs)
# and the totals. The full log is kept for anything the report leaves out.
#
# Usage: GODOT=/path/to/godot tests/run.sh [NAME] [GUT options...]
#   NAME          only scripts whose file name contains NAME (same as -gselect=NAME)
#   GUT options   passed through, e.g. -gunit_test_name=rotation
# Env:   GODOT (default: godot), TEST_LOG (default: temp file)
# Exit:  GUT's exit code (0 when every test passed).
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
project="$(cd "$here/.." && pwd)"
godot="${GODOT:-godot}"
log="${TEST_LOG:-$(mktemp --suffix=.gut.log)}"

args=()
if [ $# -gt 0 ] && [[ "$1" != -* ]]; then
	args+=("-gselect=$1")
	shift
fi
args+=("$@")

timeout 900 "$godot" --headless --path "$project" -s addons/gut/gut_cmdln.gd \
	-gconfig=.gutconfig.json -gdisable_colors -ghide_orphans "${args[@]}" >"$log" 2>&1
status=$?

# GUT colours a few lines before it reads -gdisable_colors; strip what is left.
sed -i 's/\x1b\[[0-9;]*m//g' "$log"

# GUT skips a test script that fails to load (a parse error) and can still
# report every remaining test as passed.
broken="$(grep -oE 'Failed to load script "res://tests/[^"]+"' "$log" | sort -u)"
if [ -n "$broken" ]; then
	echo "FAIL: test scripts that did not load (GUT skipped them):"
	printf '%s\n' "$broken"
	grep -E -A2 'Parse Error' "$log" | grep -vE 'GDScript backtrace|^--$' | head -n 20
	echo "Full log: $log"
	exit 1
fi
if grep -qE 'Nothing was run|Could not find script matching' "$log"; then
	echo "FAIL: no tests matched the selection: ${args[*]}"
	exit 1
fi
if ! grep -q '^= Run Summary' "$log"; then
	# GUT never got to its summary: a crash, a parse error or a timeout.
	echo "FAIL: GUT did not finish (exit $status). Last lines of $log:"
	tail -n 40 "$log"
	exit $(( status == 0 ? 1 : status ))
fi

awk -v status="$status" -v logfile="$log" '
	# Collect each test'"'"'s output; print the block only if the test failed.
	function flush() {
		if (failed) {
			printf "%s :: %s\n", script, test
			for (i = 1; i <= n && i <= 60; i++) print block[i]
			if (n > 60) printf "    ... %d more lines in the log\n", n - 60
			print ""
		}
		n = 0; failed = 0; test = ""
	}
	/^= Run Summary/ { flush(); summary = 1; next }
	summary {
		if ($1 == "Scripts" || $1 == "Tests" || $1 == "Passing" || $1 == "Failing" ||
				$1 == "Risky" || $1 == "Pending" || $1 == "Asserts" || $1 == "Time")
			totals = totals (totals == "" ? "" : ", ") $0
		if (/^---- /) result = $0
		next
	}
	/^res:\/\/tests\// { flush(); script = $0; next }
	/^\* test_/ { flush(); test = substr($0, 3); next }
	/^[0-9]+\/[0-9]+ passed\.$/ { flush(); next }
	test != "" {
		if (/\(res:\/\/addons\/gut\//) next   # GUT'"'"'s own stack frames
		if (/\[Failed\]/) failed = 1
		block[++n] = $0
	}
	END {
		gsub(/ +/, " ", totals)
		if (status == 0) printf "PASS: %s\n", totals
		else printf "FAIL: %s\n%s\nFull log: %s\n", totals, result, logfile
	}
' "$log"

exit "$status"
