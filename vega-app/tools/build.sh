#!/bin/bash
# Amazon's build tools break on paths with spaces ("Claude Code/Keith Personal"), so this copies the project to
# ~/dev/churchtvos-vega, builds there, and copies the .vpkg files back into ./build.
# Usage: tools/build.sh [Release|Debug]
set -euo pipefail
TYPE="${1:-Release}"
SRC="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$HOME/dev/churchtvos-vega"
source "$HOME/vega/env" 2>/dev/null || true
export PATH="/opt/homebrew/bin:$PATH"
mkdir -p "$WORK"
rsync -a --delete --exclude node_modules --exclude build --exclude .tmp --exclude buildinfo.json "$SRC/" "$WORK/"
cd "$WORK"
if [ ! -d node_modules ] || [ package-lock.json -nt node_modules ]; then npm ci --no-audit --no-fund; fi
npx react-native build-vega --build-type "$TYPE"
mkdir -p "$SRC/build"
rsync -a "$WORK/build/" "$SRC/build/"
find "$SRC/build" -name "*.vpkg"
