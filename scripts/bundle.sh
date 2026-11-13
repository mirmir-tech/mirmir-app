#!/usr/bin/env bash
# Builds Mirmir.app into build/.
#
#   scripts/bundle.sh [--release] [--helper /path/to/mirmir]
#
# --helper copies a mirmir binary to Contents/Helpers/mirmir; the app starts it
# when no personal server is running. Without it the app looks for mirmir on
# PATH. The bundle is ad-hoc signed; Developer ID signing and notarization are
# a release step.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

configuration=debug
helper=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --release) configuration=release; shift ;;
        --helper) helper="$2"; shift 2 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

version="${MIRMIR_APP_VERSION:-0.6.0}"
build="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

swift build -c "$configuration" --product Mirmir
binary="$(swift build -c "$configuration" --show-bin-path)/Mirmir"

app="build/Mirmir.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Helpers"
cp "$binary" "$app/Contents/MacOS/Mirmir"
sed -e "s/__VERSION__/$version/" -e "s/__BUILD__/$build/" Resources/Info.plist > "$app/Contents/Info.plist"

if [[ -n "$helper" ]]; then
    cp "$helper" "$app/Contents/Helpers/mirmir"
    codesign --force --sign - "$app/Contents/Helpers/mirmir"
fi

codesign --force --sign - "$app"
echo "built $app ($configuration, $version build $build)"
