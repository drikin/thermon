#!/bin/bash
# Build thermon (CLI) and ThermonBar.app (menu-bar) into OUT (default: this directory).
set -euo pipefail
cd "$(dirname "$0")"
OUT="${1:-.}"
mkdir -p "$OUT"
clang -O2 -fobjc-arc thermon.m -o "$OUT/thermon" -framework Foundation -framework IOKit -lIOReport
clang -O2 -fobjc-arc -c ThermonCore.m -o "$OUT/ThermonCore.o"
A="$OUT/ThermonBar.app/Contents"
mkdir -p "$A/MacOS"
cp ThermonBar-Info.plist "$A/Info.plist"
swiftc -O -parse-as-library ThermonBar.swift "$OUT/ThermonCore.o" -import-objc-header ThermonCore.h \
    -framework IOKit -lIOReport -o "$A/MacOS/ThermonBar"
codesign -s - --force "$OUT/ThermonBar.app"
echo "built: $OUT/thermon $OUT/ThermonBar.app"
