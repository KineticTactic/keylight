#!/bin/bash
set -eu
cd "$(dirname "$0")/.."
swift build -c release
app="$PWD/dist/Keylight.app"
mkdir -p "$app/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/Keylight" "$app/Contents/MacOS/"
cp Resources/Info.plist "$app/Contents/"
codesign --force --sign - "$app"
echo "$app"
