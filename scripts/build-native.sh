#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

configuration=${CONFIGURATION:-release}
identity=${SIGN_IDENTITY:-IsleKit Local Development}
architectures=${ARCHS:-$(uname -m)}
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/IsleKit-bundle.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT
app="$build_dir/IsleKit.app"
contents="$app/Contents"
extension="$contents/PlugIns/IsleKitFinderSync.appex"
mkdir -p "$contents/MacOS" "$contents/Resources" "$extension/Contents/MacOS" dist
cp App/Info.plist "$contents/Info.plist"
cp Extensions/IsleKitFinderSync/Info.plist "$extension/Contents/Info.plist"
main_bins=()
extension_bins=()
for arch in $architectures; do
    case "$arch" in arm64|x86_64) ;; *) echo "Unsupported architecture: $arch" >&2; exit 2;; esac
    swift build --build-system native -c "$configuration" --arch "$arch" --product IsleKit
    bin=$(swift build --build-system native -c "$configuration" --arch "$arch" --show-bin-path)
    main_bins+=("$bin/IsleKit")
    if [[ ! -d "$contents/Resources/IsleKitModules_DesignSystem.bundle" ]]; then
        cp -R "$bin/IsleKitModules_DesignSystem.bundle" "$contents/Resources/"
    fi
    # Compile the same shared source and Finder extension as the Xcode targets.
    mod="$build_dir/$arch"
    mkdir -p "$mod"
    xcrun swiftc -target "$arch-apple-macos13" -swift-version 6 -parse-as-library -application-extension -O \
        -emit-module -emit-object -module-name FinderActionsShared \
        -emit-module-path "$mod/FinderActionsShared.swiftmodule" \
        Packages/IsleKitModules/Sources/FinderActionsShared/FinderActions.swift -o "$mod/shared.o"
    xcrun swiftc -target "$arch-apple-macos13" -swift-version 6 -parse-as-library -application-extension -O \
        -I "$mod" "$mod/shared.o" -Xlinker -e -Xlinker _NSExtensionMain \
        Extensions/IsleKitFinderSync/FinderSync.swift -o "$mod/finder"
    extension_bins+=("$mod/finder")
done
lipo -create "${main_bins[@]}" -output "$contents/MacOS/IsleKit"
lipo -create "${extension_bins[@]}" -output "$extension/Contents/MacOS/IsleKitFinderSync"
mkdir "$build_dir/AppIcon.iconset"
cp App/Assets.xcassets/AppIcon.appiconset/*.png "$build_dir/AppIcon.iconset/"
iconutil -c icns "$build_dir/AppIcon.iconset" -o "$contents/Resources/AppIcon.icns"
cp -R App/Notices "$contents/Resources/"
scripts/embed-clipboard-key.sh "$contents" "$identity" $architectures
codesign --force --options runtime --sign "$identity" --entitlements Extensions/IsleKitFinderSync/Finder.entitlements "$extension"
codesign --force --options runtime --sign "$identity" --entitlements App/IsleKit.entitlements "$app"
codesign --verify --deep --strict "$app"
ditto "$app" dist/IsleKit.app
echo "dist/IsleKit.app"
