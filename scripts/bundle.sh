#!/usr/bin/env bash
# Builds Mirmir.app into build/ with Mirmir.xcodeproj.
#
#   scripts/bundle.sh [--release]
#
# The build embeds mirmir and MLX from the surrounding Workmir checkout (see
# scripts/xcode-helper.sh). The bundle is signed for development; Developer ID
# signing, the disk image and notarization are scripts/release.sh.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

configuration=Debug
while [[ $# -gt 0 ]]; do
    case "$1" in
        --release) configuration=Release; shift ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

version="${MIRMIR_APP_VERSION:-0.6.0}"
build="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
derived="build/DerivedData"

xcodebuild \
    -project Mirmir.xcodeproj -scheme Mirmir -configuration "$configuration" \
    -destination "generic/platform=macOS" -derivedDataPath "$derived" -quiet \
    MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build" \
    build

app="build/Mirmir.app"
rm -rf "$app"
cp -R "$derived/Build/Products/$configuration/Mirmir.app" "$app"


codesign --verify --strict --deep "$app"
echo "built $app ($configuration, $version build $build)"
