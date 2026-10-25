#!/bin/zsh
# Usage: scripts/build.sh [build|test]
cd "${0:A:h}/.." || exit 1
xcodegen generate -q >/dev/null
xcodebuild -scheme Browsi -destination 'platform=macOS' -derivedDataPath build "${1:-build}" 2>&1 \
  | grep -E "error:|warning:|^✘|Test run with|BUILD (SUCCEEDED|FAILED)|TEST (SUCCEEDED|FAILED)|\*\* " \
  | grep -v "appintentsmetadataprocessor" | sort -u | head -80
