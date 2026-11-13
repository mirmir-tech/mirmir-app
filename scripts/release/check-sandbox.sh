#!/usr/bin/env bash
# Checks the entitlements of a signed Mirmir.app: the app is sandboxed and not
# debuggable, and its bundled mirmir inherits the sandbox and nothing else.
#
#   scripts/release/check-sandbox.sh path/to/Mirmir.app
set -euo pipefail

app="$1"
helper="$app/Contents/Helpers/mirmir"
fail() { echo "error: $*" >&2; exit 1; }
entitlements() { codesign -d --entitlements - --xml "$1" 2>/dev/null | plutil -convert json -o - -; }
has() { grep -qF "\"$2\":true" <<<"$1"; }

app_entitlements="$(entitlements "$app")"
helper_entitlements="$(entitlements "$helper")"

has "$app_entitlements" com.apple.security.app-sandbox || fail "the app is not sandboxed"
if grep -q "get-task-allow" <<<"$app_entitlements$helper_entitlements"; then
    fail "get-task-allow is set, which notarization and the App Store refuse"
fi
has "$helper_entitlements" com.apple.security.app-sandbox || fail "the bundled mirmir is not sandboxed"
has "$helper_entitlements" com.apple.security.inherit || fail "the bundled mirmir does not inherit the app's sandbox"
keys="$(tr -d '{}"' <<<"$helper_entitlements" | tr ',' '\n' | cut -d: -f1 | sort | tr '\n' ' ')"
[[ "$keys" == "com.apple.security.app-sandbox com.apple.security.inherit " ]] \
    || fail "the bundled mirmir may carry only app-sandbox and inherit, has: $keys"
echo "sandbox: app and bundled mirmir are sandboxed; mirmir inherits the app's sandbox"
