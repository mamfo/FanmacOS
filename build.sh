#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/FanmacOS.app"
CONTENTS="$APP/Contents"

mkdir -p "$BUILD"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

swiftc -O -swift-version 5 -target arm64-apple-macos13.0 \
    -o "$CONTENTS/MacOS/FanmacOS" \
    "$ROOT"/Sources/*.swift

swiftc -O -swift-version 5 -target arm64-apple-macos13.0 \
    -o "$CONTENTS/MacOS/fanctl" \
    "$ROOT/Sources/SMC.swift" \
    "$ROOT/Sources/FanControl.swift" \
    "$ROOT/Sources/fanctl/main.swift"

cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"

if [[ ! -f "$ROOT/Resources/AppIcon.icns" ]]; then
    "$ROOT/scripts/build-icon.sh"
fi
cp "$ROOT/Resources/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"

codesign --force --sign - "$CONTENTS/MacOS/fanctl" >/dev/null
codesign --force --sign - "$APP" >/dev/null

echo "App criada em: $APP"
