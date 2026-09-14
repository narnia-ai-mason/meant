#!/bin/sh
set -euo pipefail

cd "$(dirname "$0")/.."
swift build -c debug --product MeantApp

app=".build/meant.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/debug/MeantApp "$app/Contents/MacOS/meant"
cp Sources/MeantApp/Info.plist "$app/Contents/Info.plist"
if [ -d .build/debug/Meant_MeantCore.bundle ]; then
  cp -R .build/debug/Meant_MeantCore.bundle "$app/Contents/Resources/Meant_MeantCore.bundle"
fi
./scripts/install-icon.sh "$app/Contents/Resources/meant.icns"
open "$app"
