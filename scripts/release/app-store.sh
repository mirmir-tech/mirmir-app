#!/usr/bin/env bash
# The Mac App Store edition of scripts/release.sh, which runs it with
# --app-store and documents its requirements.
#
#   scripts/release/app-store.sh <version> <build number> <team> <upload: true|false>
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
version="$1" build_number="$2" team="$3" upload="$4"
profile_name="${MIRMIR_APPSTORE_PROFILE:-Mirmir Mac App Store}"
bundle_id="tech.mirmir.app"
out="build/release"
archive="$out/Mirmir.xcarchive"

step() { printf '\n==> %s\n' "$*"; }
fail() { echo "error: $*" >&2; exit 1; }

identity_named() {
    security find-identity -v -p "$1" | sed -n 's/.*"\(.*\)"/\1/p' | grep -m1 -E "$2" || true
}
signer="$(identity_named codesigning '^Apple Distribution: .*\('"$team"'\)$')"
installer="$(identity_named basic '^(3rd Party Mac Developer Installer|Mac Installer Distribution): .*\('"$team"'\)$')"
[[ -n "$signer" ]] || fail "no Apple Distribution certificate for team $team in the keychain;
create it in Xcode → Settings → Accounts → Manage Certificates, or at developer.apple.com"
[[ -n "$installer" ]] || fail "no Mac Installer Distribution certificate for team $team in the keychain;
create it at developer.apple.com → Certificates"

# The profile must be a Mac App Store profile for this app and team.
profile_uuid=""
for file in ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/*.provisionprofile \
            ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/*.mobileprovision \
            ~/Library/MobileDevice/Provisioning\ Profiles/*.provisionprofile; do
    [[ -f "$file" ]] || continue
    plist="$(security cms -D -i "$file" 2>/dev/null)" || continue
    field() { plutil -extract "$1" raw -o - - <<<"$plist" 2>/dev/null || true; }
    [[ "$(field Name)" == "$profile_name" ]] || continue
    [[ "$(field Entitlements.com\\.apple\\.application-identifier)" == "$team.$bundle_id" ]] \
        || fail "profile '$profile_name' is not for $team.$bundle_id"
    [[ "$(field ProvisionsAllDevices)" != true && -z "$(field ProvisionedDevices.0)" ]] \
        || fail "profile '$profile_name' is a development or Developer ID profile, not a Mac App Store one"
    profile_uuid="$(field UUID)"
done
[[ -n "$profile_uuid" ]] || fail "no provisioning profile named '$profile_name'; create a Mac App Store
profile for $bundle_id at developer.apple.com → Profiles, double-click it, or set MIRMIR_APPSTORE_PROFILE"
if [[ "$upload" == true ]]; then
    [[ -n "${MIRMIR_ASC_KEY_ID:-}" && -n "${MIRMIR_ASC_ISSUER:-}" ]] \
        || fail "--upload needs MIRMIR_ASC_KEY_ID and MIRMIR_ASC_ISSUER (an App Store Connect API key)"
fi

rm -rf "$archive" "$out/Mirmir-$version.pkg"
mkdir -p "$out"

step "Testing MirmirKit"
swift test --quiet

# The profile reaches only the Mirmir target, through its Release setting
# PROVISIONING_PROFILE_SPECIFIER = $(MIRMIR_PROVISIONING_PROFILE): a setting
# on the command line applies to every target, and the SwiftPM resource
# bundles refuse a provisioning profile.
step "Archiving Mirmir $version ($build_number) for the Mac App Store, signed by $signer"
xcodebuild -project Mirmir.xcodeproj -scheme Mirmir -configuration Release \
    -destination "generic/platform=macOS" -derivedDataPath "$out/DerivedData-AppStore" -quiet \
    -archivePath "$archive" \
    MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build_number" \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$signer" DEVELOPMENT_TEAM="$team" \
    MIRMIR_PROVISIONING_PROFILE="$profile_uuid" \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    archive
app="$archive/Products/Applications/Mirmir.app"

step "Checking the app"
codesign --verify --deep --strict --verbose=2 "$app"
[[ -f "$app/Contents/embedded.provisionprofile" ]] || fail "the provisioning profile is not embedded"
"$root/scripts/release/check-sandbox.sh" "$app"
# App Store Connect refuses an app whose signature lacks the identifiers
# from its profile.
signed="$(codesign -d --entitlements - --xml "$app" 2>/dev/null | plutil -convert json -o - -)"
grep -qF "\"com.apple.application-identifier\":\"$team.$bundle_id\"" <<<"$signed" \
    || fail "the app is signed without com.apple.application-identifier $team.$bundle_id"
grep -qF "\"com.apple.developer.team-identifier\":\"$team\"" <<<"$signed" \
    || fail "the app is signed without com.apple.developer.team-identifier $team"
# The helper inherits the app's sandbox, so it runs only as the app's child
# (alone it traps); check the binary instead of running it.
lipo -archs "$app/Contents/Helpers/mirmir" | grep -qx arm64 || { echo "error: the bundled mirmir is not arm64" >&2; exit 1; }
lipo -archs "$app/Contents/MacOS/Mirmir" | grep -qx arm64 || fail "the app is not arm64 only"

step "Packaging"
pkg="$out/Mirmir-$version.pkg"
productbuild --component "$app" /Applications --sign "$installer" "$pkg"
pkgutil --check-signature "$pkg"

if [[ "$upload" == true ]]; then
    step "Validating and uploading to App Store Connect"
    auth=(--apiKey "$MIRMIR_ASC_KEY_ID" --apiIssuer "$MIRMIR_ASC_ISSUER")
    xcrun altool --validate-app --type macos --file "$pkg" "${auth[@]}"
    xcrun altool --upload-app --type macos --file "$pkg" "${auth[@]}"
    echo "uploaded $pkg; it appears in App Store Connect → TestFlight once processed"
else
    echo "built $pkg; upload it with Transporter or rerun with --app-store --upload"
fi
