#!/bin/zsh
set -euo pipefail
PROJECT_ROOT="${0:A:h:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mkdir -p "$PROJECT_ROOT/work"
xcrun swiftc -parse-as-library \
  "$PROJECT_ROOT/MacIsland/Screen/ScreenGeometry.swift" \
  "$PROJECT_ROOT"/MacIsland/Island/*.swift \
  "$PROJECT_ROOT"/MacIsland/Window/*.swift \
  "$PROJECT_ROOT/Tests/FrameworkChecks.swift" \
  -o "$PROJECT_ROOT/work/FrameworkChecks"
"$PROJECT_ROOT/work/FrameworkChecks"
