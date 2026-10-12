#!/usr/bin/env bash
# Quality gate: build the place, strict type-check every script, lint, format-check and
# run the offline Lune tests.
# Run from anywhere:  ./scripts/check.sh      (needs the tools from rokit.toml)
set -euo pipefail
cd "$(dirname "$0")/.."

CACHE=.luau-lsp
mkdir -p "$CACHE"

# Roblox API type definitions for luau-lsp (downloaded once, then cached).
if [ ! -s "$CACHE/globalTypes.d.luau" ]; then
	echo "Downloading Roblox type definitions..."
	curl -sSfL -o "$CACHE/globalTypes.d.luau" \
		https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.None.d.luau
fi

echo "== rojo build"
rojo build default.project.json --output "$CACHE/check.rbxl"
rojo sourcemap default.project.json --output sourcemap.json

echo "== luau-lsp analyze (strict)"
luau-lsp analyze \
	--definitions=@roblox="$CACHE/globalTypes.d.luau" \
	--sourcemap=sourcemap.json \
	--base-luaurc=.luaurc \
	--ignore="src/server/Vendor/**" \
	src

echo "== selene"
selene src

echo "== stylua --check"
stylua --check src

echo "== lune tests (offline: utils + map contract)"
lune run tests/run

echo "All checks passed."
