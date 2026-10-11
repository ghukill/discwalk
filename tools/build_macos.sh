#!/usr/bin/env bash
# Export and package the version in project.godot for macOS (native Apple Silicon + Intel).
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
project="$root/project.godot"
godot=${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}

fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }

[[ $(uname -s) == Darwin ]] || fail 'This script requires macOS (ditto and codesign).'
[[ -x "$godot" ]] || fail "Godot not found at $godot (set GODOT_BIN to its executable)."
command -v ditto >/dev/null || fail 'ditto is not available.'

# One source of truth for the app metadata, release folder, and archive name.
version=$(sed -nE 's/^config\/version="([0-9]+(\.[0-9]+){1,2})"$/\1/p' "$project")
[[ $version =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] || fail 'Set config/version="0.1" (or another numeric version) in project.godot.'
release_dir="$root/builds/v$version"
app="$release_dir/discwalk.app"
archive="$release_dir/discwalk-v$version-macos-universal.zip"

# Never silently replace a versioned release. Delete the artifacts to rebuild it.
[[ ! -e "$app" && ! -e "$archive" ]] || fail "v$version already has a build; remove its .app and .zip or bump config/version."
mkdir -p "$release_dir"

printf 'Importing resources with %s...\n' "$godot"
"$godot" --headless --path "$root" --editor --import
printf 'Exporting v%s to %s...\n' "$version" "$app"
"$godot" --headless --path "$root" --export-release macOS "$app"

# Ensure both architectures and the intended version made it into the bundle.
[[ $(plutil -extract CFBundleShortVersionString raw -o - "$app/Contents/Info.plist") == "$version" ]] || fail 'Exported app version does not match project.godot.'
[[ $(plutil -extract CFBundleVersion raw -o - "$app/Contents/Info.plist") == "$version" ]] || fail 'Exported bundle version does not match project.godot.'
lipo "$app/Contents/MacOS/discwalk" -verify_arch arm64 x86_64 || fail 'Export lacks a Universal 2 binary.'
codesign --verify --deep --strict "$app" || fail 'Exported app failed signature verification.'

printf 'Creating %s...\n' "$archive"
ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
printf 'Ready:\n  %s\n  %s\n' "$app" "$archive"
