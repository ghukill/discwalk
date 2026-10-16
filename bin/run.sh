#!/usr/bin/env bash
# Run discwalk from source, finding a Godot 4 executable on this machine.
#
#   bin/run.sh                                   # just play (maximized window)
#   bin/run.sh --windowed                        # the 1600x900 window (or --fullscreen)
#   bin/run.sh --block-size=0.5 --world=distance # game flags (passed after Godot's --)
#   bin/run.sh --headless --script res://tools/smoke_test.gd -- --block-size=1
#                                                # with a --, the left side goes to Godot
#
# Set GODOT_BIN to skip the search and use a specific executable.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }

find_godot() {
	local name
	for name in godot godot4; do
		if command -v "$name" >/dev/null; then
			command -v "$name"
			return
		fi
	done

	# macOS app bundles, then Linux downloads (unzipped single executables). Later
	# globs sort newer versions last, so take the last match in each location.
	local candidates=() pattern match
	for pattern in \
		"/Applications/Godot.app/Contents/MacOS/Godot" \
		"$HOME/Applications/Godot.app/Contents/MacOS/Godot" \
		"/Applications/Godot_v4*.app/Contents/MacOS/Godot" \
		"$HOME/Applications/Godot_v4*.app/Contents/MacOS/Godot" \
		"$root/../tools/godot/Godot_v4*_linux.*" \
		"$HOME/.local/bin/Godot_v4*_linux.*" \
		"$HOME/bin/Godot_v4*_linux.*"; do
		match=""
		for f in $pattern; do
			[[ -x $f && ! -d $f ]] && match=$f
		done
		[[ -n $match ]] && candidates+=("$match")
	done

	[[ ${#candidates[@]} -gt 0 ]] || return 1
	printf '%s\n' "${candidates[0]}"
}

if [[ -n ${GODOT_BIN:-} ]]; then
	[[ -x $GODOT_BIN && ! -d $GODOT_BIN ]] || fail "GODOT_BIN=$GODOT_BIN is not an executable."
	godot=$GODOT_BIN
else
	godot=$(find_godot) || fail 'Godot 4 not found. Install it (see README) or set GODOT_BIN to its executable.'
fi

# With a --, everything before it is for Godot and everything after for the game.
# Without one, every argument is a game flag.
godot_args=()
game_args=()
if [[ " $* " == *" -- "* ]]; then
	while [[ $# -gt 0 && $1 != -- ]]; do
		godot_args+=("$1")
		shift
	done
	shift
	game_args=("$@")
else
	game_args=("$@")
fi

# Window flags are Godot's, wherever they were typed. Default to a maximized
# window unless one was given (or there's no window at all).
window_flags=" --fullscreen -f --maximized -m --windowed -w --headless "
rest=()
for a in ${game_args[@]+"${game_args[@]}"}; do
	if [[ $window_flags == *" $a "* ]]; then godot_args+=("$a"); else rest+=("$a"); fi
done
game_args=(${rest[@]+"${rest[@]}"})
has_window_flag=false
for a in ${godot_args[@]+"${godot_args[@]}"}; do
	if [[ $window_flags == *" $a "* ]]; then has_window_flag=true; fi
done
$has_window_flag || godot_args=(--maximized ${godot_args[@]+"${godot_args[@]}"})

printf 'Using %s (%s)\n' "$godot" "$("$godot" --version 2>/dev/null | head -n1)" >&2
exec "$godot" --path "$root" ${godot_args[@]+"${godot_args[@]}"} -- ${game_args[@]+"${game_args[@]}"}
