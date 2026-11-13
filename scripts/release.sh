#!/usr/bin/env bash
# Builds, signs, notarizes and packages Mirmir for distribution. macOS only.
#
#   scripts/release.sh [--skip-notarize]
#   scripts/release.sh --app-store [--upload]
#
#   MIRMIR_APP_VERSION     marketing version (default 0.6.0)
#   MIRMIR_SIGN_IDENTITY   code signing identity (default "Developer ID Application")
#   MIRMIR_TEAM_ID         team of that identity (default 5AH2Q9L8R2)
#   MIRMIR_NOTARY_PROFILE  notarytool keychain profile (default mirmir-notary)
#
# Create the notarytool profile once:
#   xcrun notarytool store-credentials mirmir-notary \
#       --apple-id you@example.com --team-id 5AH2Q9L8R2 --password <app-specific>
#
# --skip-notarize builds and signs everything but does not notarize: for a
# look at the disk image on this Mac. Other Macs refuse such an image.
#
# Produces build/release/Mirmir-<version>.dmg and build/release/Mirmir-macOS.dmg
# (the same file under the stable name the website links to through
# releases/latest/download/). The app contains the mirmir runtime and MLX
# (see scripts/xcode-helper.sh); it needs nothing installed.
#
# --app-store builds the Mac App Store edition instead: an archive signed with
# Apple Distribution and the Mac App Store provisioning profile, packaged as
# build/release/Mirmir-<version>.pkg, signed with the installer certificate.
# --upload also sends it to App Store Connect. It needs, from the developer
# account: the Apple Distribution and Mac Installer Distribution certificates
# in the login keychain, a Mac App Store profile for tech.mirmir.app (installed
# by double-clicking it) and an App Store Connect record for the app.
#
#   MIRMIR_APPSTORE_PROFILE  name of that profile (default "Mirmir Mac App Store")
#   MIRMIR_ASC_KEY_ID        App Store Connect API key for --upload, its .p8 in
#   MIRMIR_ASC_ISSUER        ~/.appstoreconnect/private_keys, and its issuer
#
# Both editions run sandboxed (Resources/Mirmir.entitlements): the app's
# server lives in its container, apart from the mirmir CLI.
#
# Laying out the disk image window drives Finder through AppleScript: the
# first run asks to let the terminal control Finder.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

notarize=true
app_store=false
upload=false
for argument in "$@"; do
    case "$argument" in
        --skip-notarize) notarize=false ;;
        --app-store) app_store=true ;;
        --upload) upload=true ;;
        *) echo "unknown argument: $argument" >&2; exit 2 ;;
    esac
done

version="${MIRMIR_APP_VERSION:-0.6.0}"
build_number="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
identity="${MIRMIR_SIGN_IDENTITY:-Developer ID Application}"
team="${MIRMIR_TEAM_ID:-5AH2Q9L8R2}"
profile="${MIRMIR_NOTARY_PROFILE:-mirmir-notary}"
volume="Mirmir"
out="build/release"
work="$out/work"

step() { printf '\n==> %s\n' "$*"; }
fail() { echo "error: $*" >&2; exit 1; }

if $upload && ! $app_store; then fail "--upload goes with --app-store"; fi
if $app_store; then
    exec "$root/scripts/release/app-store.sh" "$version" "$build_number" "$team" "$upload"
fi

if $notarize && ! xcrun notarytool history --keychain-profile "$profile" >/dev/null 2>&1; then
    echo "error: no notarytool profile '$profile'; create it (see the header) or pass --skip-notarize" >&2
    exit 1
fi

rm -rf "$work" "$out/Mirmir.app"
mkdir -p "$work"

step "Testing MirmirKit"
swift test --quiet

step "Building Mirmir $version ($build_number), signed by $identity"
xcodebuild -project Mirmir.xcodeproj -scheme Mirmir -configuration Release \
    -destination "generic/platform=macOS" -derivedDataPath "$out/DerivedData" -quiet \
    MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build_number" \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$identity" DEVELOPMENT_TEAM="$team" \
    ENABLE_HARDENED_RUNTIME=YES OTHER_CODE_SIGN_FLAGS="--timestamp" \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    build
app="$out/Mirmir.app"
ditto "$out/DerivedData/Build/Products/Release/Mirmir.app" "$app"

step "Checking the signature"
codesign --verify --deep --strict --verbose=2 "$app"
details="$(codesign -dvv "$app" 2>&1)"
grep -q "Authority=Developer ID Application" <<<"$details" || { echo "error: not signed with a Developer ID" >&2; exit 1; }
grep -q "flags=.*runtime" <<<"$details" || { echo "error: hardened runtime is off" >&2; exit 1; }
"$root/scripts/release/check-sandbox.sh" "$app"

step "Checking the bundled runtime"
# The helper inherits the app's sandbox, so it runs only as the app's child
# (alone it traps); check the binary instead of running it.
lipo -archs "$app/Contents/Helpers/mirmir" | grep -qx arm64 || { echo "error: the bundled mirmir is not arm64" >&2; exit 1; }
while IFS= read -r -d '' file; do
    if file -b "$file" | grep -q "Mach-O" && otool -L "$file" | tail -n +2 | grep -q "/Users/"; then
        echo "error: $file links a library on this machine:" >&2
        otool -L "$file" | grep "/Users/" >&2
        exit 1
    fi
done < <(find "$app/Contents" -type f -print0)
lipo -archs "$app/Contents/MacOS/Mirmir" | grep -qx arm64 || { echo "error: the app is not arm64 only" >&2; exit 1; }

step "Drawing the disk image background"
swift scripts/dmg/background.swift "$work/background.png" 1 "$version"
swift scripts/dmg/background.swift "$work/background@2x.png" 2 "$version"
tiffutil -cathidpicheck "$work/background.png" "$work/background@2x.png" -out "$work/background.tiff" >/dev/null

step "Assembling the disk image"
staging="$work/staging"
mkdir -p "$staging/.background"
ditto "$app" "$staging/Mirmir.app"
ln -s /Applications "$staging/Applications"
cp "$work/background.tiff" "$staging/.background/background.tiff"

if [[ -d "/Volumes/$volume" ]]; then hdiutil detach "/Volumes/$volume" -force -quiet || true; fi
size_mb=$(( $(du -sm "$staging" | cut -f1) + 40 ))
hdiutil create -quiet -volname "$volume" -srcfolder "$staging" -fs HFS+ -format UDRW -size "${size_mb}m" -ov "$work/rw.dmg"
device="$(hdiutil attach "$work/rw.dmg" -readwrite -noverify -noautoopen 2>/dev/null | awk '/Apple_HFS/ {print $1}')"
mount="/Volumes/$volume"

# Finder's bounds are the whole window; make the content area exactly the
# background's 660×400 pt.
window_height="$(swift - <<'SWIFT'
import AppKit
let frame = NSWindow.frameRect(forContentRect: NSRect(x: 0, y: 0, width: 660, height: 400), styleMask: [.titled, .closable, .miniaturizable])
print(Int(frame.height.rounded()))
SWIFT
)"
osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$volume"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 860, $((120 + window_height))}
        set options to the icon view options of container window
        set arrangement of options to not arranged
        set icon size of options to 128
        set text size of options to 13
        set label position of options to bottom
        set background picture of options to file ".background:background.tiff"
        set extension hidden of item "Mirmir.app" to true
        set position of item "Mirmir.app" of container window to {170, 190}
        set position of item "Applications" of container window to {490, 190}
        close
        open
        update without registering applications
        delay 2
        close
    end tell
end tell
APPLESCRIPT
# The volume icon: added to the mounted image (hdiutil -srcfolder drops it)
# and flagged after Finder has written its layout, which can clear the flag.
cp "$app/Contents/Resources/AppIcon.icns" "$mount/.VolumeIcon.icns"
SetFile -c icnC "$mount/.VolumeIcon.icns"
SetFile -a C "$mount"
chmod -Rf go-w "$mount" 2>/dev/null || true
sync
for attempt in 1 2 3 4 5; do
    hdiutil detach "$device" -quiet && break
    sleep 2
done

dmg="$out/Mirmir-$version.dmg"
rm -f "$dmg"
hdiutil convert -quiet "$work/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$dmg"
codesign --force --timestamp --sign "$identity" "$dmg"

if $notarize; then
    step "Notarizing (this waits for Apple)"
    xcrun notarytool submit "$dmg" --keychain-profile "$profile" --wait
    xcrun stapler staple "$dmg"
    xcrun stapler validate "$dmg"
    spctl --assess --type open --context context:primary-signature --verbose "$dmg"
else
    step "Skipping notarization: other Macs will refuse this image"
fi

cp "$dmg" "$out/Mirmir-macOS.dmg"
rm -rf "$work"
shasum -a 256 "$dmg"
echo "built $dmg$($notarize && echo ", notarized and stapled" || echo ", not notarized")"
