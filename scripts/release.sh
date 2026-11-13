#!/usr/bin/env bash
# Signs, packages, notarizes and staples Mirmir for distribution. macOS only.
#
#   MIRMIR_SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" \
#   MIRMIR_NOTARY_PROFILE=mirmir-notary \
#   scripts/release.sh
#
# Create the notarytool profile once:
#   xcrun notarytool store-credentials mirmir-notary \
#       --apple-id you@example.com --team-id TEAMID --password <app-specific>
#
# Produces build/Mirmir-<version>.dmg and build/Mirmir-macOS.dmg (the same
# file under the stable name the website links to through
# releases/latest/download/). The app uses `mirmir` from PATH; no helper is
# bundled, because mirmir links libmlx.dylib dynamically.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

version="${MIRMIR_APP_VERSION:-0.6.0}"
identity="${MIRMIR_SIGN_IDENTITY:?set MIRMIR_SIGN_IDENTITY to a Developer ID Application identity}"
profile="${MIRMIR_NOTARY_PROFILE:?set MIRMIR_NOTARY_PROFILE to a notarytool keychain profile}"

swift test
MIRMIR_APP_VERSION="$version" scripts/bundle.sh --release

app="build/Mirmir.app"
sign() { codesign --force --options runtime --timestamp --sign "$identity" "$@"; }
if [[ -f "$app/Contents/Helpers/mirmir" ]]; then sign "$app/Contents/Helpers/mirmir"; fi
sign "$app/Contents/MacOS/Mirmir"
sign "$app"
codesign --verify --strict --deep --verbose=2 "$app"

dmg="build/Mirmir-$version.dmg"
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
cp -R "$app" "$staging/"
ln -s /Applications "$staging/Applications"
rm -f "$dmg"
hdiutil create -volname "Mirmir $version" -srcfolder "$staging" -format UDZO "$dmg"
codesign --force --timestamp --sign "$identity" "$dmg"

xcrun notarytool submit "$dmg" --keychain-profile "$profile" --wait
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
spctl --assess --type open --context context:primary-signature --verbose "$dmg"

cp "$dmg" build/Mirmir-macOS.dmg
shasum -a 256 "$dmg" build/Mirmir-macOS.dmg
echo "notarized $dmg; attach both files to the mirmir-app v$version GitHub release"
