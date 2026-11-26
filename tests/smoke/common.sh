# Shared by the smoke scripts. Source it; it defines functions only.

# Removes the colour codes the game's logger writes, in place.
strip_colours() {
	sed -i 's/\x1b\[[0-9;]*m//g' "$1"
}

# Prints the error lines in LOG that no pattern in the KNOWN files matches.
# Known files hold extended regexes, one per line; lines starting with # are comments.
# Usage: unexpected_errors LOG KNOWN...
unexpected_errors() {
	local log="$1"
	shift
	local errors patterns
	errors="$(grep -E '^(ERROR|SCRIPT ERROR|USER ERROR|USER SCRIPT ERROR):|Parse Error' "$log" || true)"
	patterns="$(cat "$@" | grep -vE '^\s*(#|$)' || true)"
	if [ -n "$patterns" ] && [ -n "$errors" ]; then
		errors="$(printf '%s\n' "$errors" | grep -vEf <(printf '%s\n' "$patterns") || true)"
	fi
	if [ -n "$errors" ]; then
		printf '%s\n' "$errors" | sort | uniq -c | sort -rn
	fi
}
