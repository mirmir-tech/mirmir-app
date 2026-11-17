#!/usr/bin/env bash
# Checks that no binary in a Mirmir.app uses the private macOS interfaces
# mirmir could pull in: libmir's `metal-telemetry` GPU sampling (IOReport,
# IOHID events). scripts/xcode-helper.sh leaves it out of every edition; App
# Review rejects it.
#
#   scripts/release/check-private-api.sh path/to/Mirmir.app
set -euo pipefail

app="$1"
fail() { echo "error: $*" >&2; exit 1; }

private_api='^_(IOReport|IOHIDEventSystemClient|IOHIDServiceClientCopyEvent|IOHIDEventGet)'
while IFS= read -r -d '' file; do
    file -b "$file" | grep -q Mach-O || continue
    found="$(nm -u "$file" 2>/dev/null | grep -E "$private_api" || true)"
    [[ -z "$found" ]] || fail "${file#"$app/"} uses private macOS interfaces:
$found"
    ! otool -L "$file" | grep -q libIOReport || fail "${file#"$app/"} links libIOReport"
done < <(find "$app/Contents" -type f -print0)
echo "private API: no binary uses IOReport or IOHID events"
