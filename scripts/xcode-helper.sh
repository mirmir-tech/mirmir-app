#!/usr/bin/env bash
# Xcode build phase: builds mirmir from the surrounding Workmir checkout and
# embeds the whole runtime, so the app runs on a Mac without mirmir or MLX:
#
#   Contents/Helpers/mirmir
#   Contents/Frameworks/MLX.framework   libmlx, with mlx.metallib in its
#                                       Resources, where MLX looks for it
#   Contents/Frameworks/libjaccl.dylib
#
# Install names are rewritten from the build machine's MLX prefix to @rpath,
# and every piece is signed with the app's identity and hardened runtime
# (with a secure timestamp outside Debug), inside out, before Xcode signs
# the app.
#
# Works from a clean checkout: it installs the MLX release pinned in
# scripts/mlx/version.env when .native/mlx does not point at it (first run
# takes several minutes), then runs cargo, which reuses its cache afterwards.
# Outside Workmir (no ../mirmir crate next to this repository) it does
# nothing, and the app falls back to mirmir on PATH.
#
#   MIRMIR_HELPER=skip       do not build or embed the runtime (no local server)
#   MIRMIR_CARGO_PROFILE=dev build an unoptimized server (default: release)
set -euo pipefail

app_root="$(cd "$(dirname "$0")/.." && pwd)"
workmir="$(cd "$app_root/.." && pwd)"
crate="$workmir/mirmir"

if [[ "${MIRMIR_HELPER:-}" == skip ]]; then
    echo "note: MIRMIR_HELPER=skip; the app has no local server, only remote ones"
    exit 0
fi
if [[ ! -f "$crate/Cargo.toml" || ! -f "$workmir/.cargo/config.toml" ]]; then
    echo "warning: no Workmir mirmir checkout at $crate; the app uses mirmir from PATH"
    exit 0
fi

profile="${MIRMIR_CARGO_PROFILE:-release}"
case "$profile" in
    release) out_dir=release ;;
    dev | debug) profile=dev; out_dir=debug ;;
    *) echo "error: unsupported MIRMIR_CARGO_PROFILE=$profile" >&2; exit 1 ;;
esac

# Xcode exports SDKROOT, MACOSX_DEPLOYMENT_TARGET, CC and many more. They would
# make MLX a separate deployment-target build without NAX kernels and change
# the native bridge, invalidating the terminal's cargo cache. Run the native
# builds with the environment a login shell would have.
clean_path="$HOME/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
clean_env=(env -i HOME="$HOME" USER="${USER:-}" TMPDIR="${TMPDIR:-/tmp}" PATH="$clean_path")
for name in RUSTUP_HOME CARGO_HOME XDG_CACHE_HOME MLX_BUILD_JOBS; do
    [[ -n "${!name:-}" ]] && clean_env+=("$name=${!name}")
done

require() {
    "${clean_env[@]}" sh -c "command -v $1" >/dev/null || { echo "error: $1 not found; $2" >&2; exit 1; }
}
require cargo "install Rust with rustup (https://rustup.rs); the toolchain comes from rust-toolchain.toml"
require git "install the Xcode command line tools"
"${clean_env[@]}" xcrun --sdk macosx --find metal >/dev/null 2>&1 \
    || { echo "error: Metal compiler missing; run: xcodebuild -downloadComponent MetalToolchain" >&2; exit 1; }

# The pinned MLX release, as scripts/mlx/setup.sh installs it.
. "$workmir/scripts/mlx/version.env"
mlx_link="$workmir/.native/mlx"
mlx_ready() {
    [[ -f "$mlx_link/include/mlx/version.h" && -f "$mlx_link/lib/libmlx.dylib" && -f "$mlx_link/lib/mlx.metallib" ]] || return 1
    case "$(cd "$mlx_link" && pwd -P)" in
        */mlx-"$MLX_VERSION"/install*) return 0 ;;
        *) return 1 ;;
    esac
}
if ! mlx_ready; then
    require cmake "run: brew install cmake ninja"
    require ninja "run: brew install cmake ninja"
    echo "MLX $MLX_VERSION is not installed at $mlx_link; running scripts/mlx/setup.sh (several minutes on first run)"
    "${clean_env[@]}" sh "$workmir/scripts/mlx/setup.sh"
    mlx_ready || { echo "error: scripts/mlx/setup.sh did not leave MLX $MLX_VERSION at $mlx_link" >&2; exit 1; }
fi

echo "building mirmir ($profile) in $crate against MLX $MLX_VERSION"
(cd "$crate" && "${clean_env[@]}" cargo build --profile "$profile" --bin mirmir)

binary="$crate/target/$out_dir/mirmir"
mlx_lib="$(cd "$mlx_link" && pwd -P)/lib"
contents="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH"
helpers="$contents/Helpers"
frameworks="$contents/Frameworks"
framework="$frameworks/MLX.framework"

# The embedded copies are rewritten and signed, so compare against a stamp of
# their sources. Touching them when nothing changed would break the app's seal
# on incremental builds, where Xcode does not re-sign.
stamp="$DERIVED_FILE_DIR/mirmir-runtime.sha256"
digest="$(cat "$binary" "$mlx_lib/libmlx.dylib" "$mlx_lib/libjaccl.dylib" "$mlx_lib/mlx.metallib" "$app_root/Resources/MirmirHelper.entitlements" | shasum -a 256 | cut -d' ' -f1)"
identity="${EXPANDED_CODE_SIGN_IDENTITY:--}"
if [[ "${CONFIGURATION:-Debug}" == Debug ]]; then timestamp="--timestamp=none"; else timestamp="--timestamp"; fi

if [[ ! -x "$helpers/mirmir" || ! -d "$framework" || "$(cat "$stamp" 2>/dev/null)" != "$digest" ]]; then
    echo "embedding mirmir and MLX $MLX_VERSION"
    rm -rf "$helpers/mirmir" "$framework" "$frameworks/libjaccl.dylib"
    mkdir -p "$helpers" "$framework/Versions/A/Resources"

    cp "$mlx_lib/libjaccl.dylib" "$frameworks/libjaccl.dylib"
    cp "$mlx_lib/libmlx.dylib" "$framework/Versions/A/MLX"
    cp "$mlx_lib/mlx.metallib" "$framework/Versions/A/Resources/mlx.metallib"
    cat > "$framework/Versions/A/Resources/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>MLX</string>
    <key>CFBundleIdentifier</key><string>tech.mirmir.app.MLX</string>
    <key>CFBundleName</key><string>MLX</string>
    <key>CFBundlePackageType</key><string>FMWK</string>
    <key>CFBundleShortVersionString</key><string>$MLX_VERSION</string>
    <key>CFBundleVersion</key><string>$MLX_VERSION</string>
</dict>
</plist>
PLIST
    ln -s A "$framework/Versions/Current"
    ln -s Versions/Current/MLX "$framework/MLX"
    ln -s Versions/Current/Resources "$framework/Resources"
    cp "$binary" "$helpers/mirmir"
    chmod u+w "$frameworks/libjaccl.dylib" "$framework/Versions/A/MLX" "$helpers/mirmir"

    # From the build machine's MLX prefix to paths inside the bundle.
    install_name_tool -id @rpath/libjaccl.dylib "$frameworks/libjaccl.dylib"
    install_name_tool -id @rpath/MLX.framework/Versions/A/MLX \
        -change "$mlx_lib/libjaccl.dylib" @rpath/libjaccl.dylib \
        -add_rpath @loader_path/../../.. "$framework/Versions/A/MLX"
    install_name_tool -change "$mlx_lib/libmlx.dylib" @rpath/MLX.framework/Versions/A/MLX \
        -add_rpath @executable_path/../Frameworks "$helpers/mirmir"
    if otool -L "$helpers/mirmir" "$framework/Versions/A/MLX" | grep -q "$mlx_lib"; then
        echo "error: an embedded binary still links $mlx_lib" >&2
        exit 1
    fi

    # Inside out: the libraries, the framework, then the helper.
    sign() { codesign --force --sign "$identity" --options runtime "$timestamp" "$@"; }
    sign "$frameworks/libjaccl.dylib"
    sign "$framework"
    # The helper inherits the app's sandbox; App Store helpers carry exactly
    # app-sandbox and inherit.
    sign --identifier tech.mirmir.app.server --entitlements "$app_root/Resources/MirmirHelper.entitlements" "$helpers/mirmir"
    mkdir -p "$DERIVED_FILE_DIR"
    echo "$digest" > "$stamp"
fi
# The helper inherits the app's sandbox, so it runs only as the app's child
# (alone it traps) and cannot be probed here. Check what can be: every piece
# is signed, and the helper links nothing outside the bundle.
for piece in "$frameworks/libjaccl.dylib" "$framework" "$helpers/mirmir"; do
    codesign --verify --strict "$piece" || { echo "error: $piece is not validly signed" >&2; exit 1; }
done
codesign -d --entitlements - "$helpers/mirmir" 2>/dev/null | grep -q "com.apple.security.inherit" \
    || { echo "error: the embedded mirmir does not inherit the app's sandbox" >&2; exit 1; }
version="$(sed -n 's/^version = "\(.*\)"/\1/p' "$crate/Cargo.toml" | head -n 1)"
echo "embedded mirmir $version with MLX $MLX_VERSION (not launched: it runs only inside the app)"
