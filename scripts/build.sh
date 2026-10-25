#!/bin/zsh
# Usage: scripts/build.sh [build|test]   — prints only compiler diagnostics and test results.
cd "${0:A:h}/.." || exit 1
xcodegen generate -q >/dev/null
log=$(mktemp -t browsi-build)
xcodebuild -scheme Browsi -destination 'platform=macOS' -derivedDataPath build "${1:-build}" >"$log" 2>&1
grep -aE "^/.*(error|warning): |^✘|Test run with|\*\* (BUILD|TEST) " "$log" | sort -u | head -60
echo "full log: $log"
