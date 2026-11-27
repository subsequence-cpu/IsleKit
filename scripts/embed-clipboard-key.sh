#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
contents=$1
identity=$2
shift 2
stage=$(mktemp -d "${TMPDIR:-/tmp}/IsleKit-key.XXXXXX")
trap 'rm -rf "$stage"' EXIT
service="$contents/XPCServices/ClipboardKey.xpc"
mkdir -p "$service/Contents/MacOS"
slices=()
for arch in "$@"; do
    xcrun swiftc -target "$arch-apple-macos13" -swift-version 6 -O -whole-module-optimization \
        -module-name ClipboardKey \
        Packages/IsleKitModules/Sources/ClipboardPlugin/ClipboardKey.swift \
        Services/ClipboardKey/main.swift -o "$stage/$arch"
    slices+=("$stage/$arch")
done
lipo -create "${slices[@]}" -output "$service/Contents/MacOS/ClipboardKey"
cp Services/ClipboardKey/Info.plist "$service/Contents/Info.plist"
codesign --force --options runtime --sign "$identity" "$service"
