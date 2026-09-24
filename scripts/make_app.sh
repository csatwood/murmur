#!/bin/bash
# Builds Murmur.app from the SwiftPM release binary.
set -euo pipefail

cd "$(dirname "$0")/.."

# The app targets macOS 26 (see LSMinimumSystemVersion below). This script was
# authored on a macOS 26 system, where the command-line tools' default SDK also
# matched. On a machine whose command-line tools have since moved to a newer
# default SDK (for example macOS 27), building against that default breaks the
# SwiftUI macro plugin lookup: the compiler reports "external macro
# implementation type 'SwiftUIMacros.StateMacro' could not be found ... plugin
# for module 'SwiftUIMacros' not found" for every @State. Building against an
# installed SDK that matches the target avoids it.
#
# So when the caller has not already chosen an SDK, and the default SDK is newer
# than the target, auto-select the newest installed macOS 26 SDK. An explicit
# --sdk always wins, and a machine whose default already matches is unchanged.
TARGET_SDK_MAJOR=26

caller_set_sdk=0
for arg in "$@"; do
    if [ "$arg" = "--sdk" ]; then
        caller_set_sdk=1
        break
    fi
done

sdk_args=()
if [ "$caller_set_sdk" -eq 0 ]; then
    default_sdk_path="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)"
    default_sdk_version="$(xcrun --sdk macosx --show-sdk-version 2>/dev/null || true)"
    default_sdk_major="${default_sdk_version%%.*}"
    if [ -n "$default_sdk_major" ] && [ "$default_sdk_major" -gt "$TARGET_SDK_MAJOR" ] 2>/dev/null; then
        # A named lookup like `xcrun --sdk macosx26` fails: xcrun wants the full
        # minor version, which we cannot assume. Enumerate the installed SDKs
        # instead and pick the newest one matching the target major.
        sdk_dir="$(dirname "$default_sdk_path")"
        best_sdk=""
        best_ver=""
        for candidate in "$sdk_dir"/MacOSX${TARGET_SDK_MAJOR}*.sdk; do
            [ -d "$candidate" ] || continue
            ver="$(/usr/libexec/PlistBuddy -c 'Print Version' "$candidate/SDKSettings.plist" 2>/dev/null || true)"
            [ -n "$ver" ] || continue
            if [ -z "$best_ver" ] || [ "$(printf '%s\n%s\n' "$best_ver" "$ver" | sort -V | tail -1)" = "$ver" ]; then
                best_sdk="$candidate"
                best_ver="$ver"
            fi
        done
        if [ -n "$best_sdk" ]; then
            echo "Default SDK is $default_sdk_version but the app targets macOS $TARGET_SDK_MAJOR;" >&2
            echo "building against $best_sdk ($best_ver) to keep the SwiftUI macro plugin resolvable." >&2
            sdk_args=(--sdk "$best_sdk")
        else
            echo "WARNING: default SDK is $default_sdk_version but no macOS $TARGET_SDK_MAJOR SDK is" >&2
            echo "installed. Building against the default may fail on the SwiftUI macros; pass" >&2
            echo "--sdk /path/to/MacOSX${TARGET_SDK_MAJOR}.sdk or install the matching SDK." >&2
        fi
    fi
fi

swift build -c release ${sdk_args[@]+"${sdk_args[@]}"} "$@"

APP="build/Murmur.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/Murmur "$APP/Contents/MacOS/Murmur"

# Bundled fonts: copied straight into Contents/Resources rather than
# SwiftPM's generated Murmur_Murmur.bundle, which it expects at the .app's
# top level — codesign won't seal resources living outside Contents/, and
# fails to verify. FontLoader checks Bundle.main (this location) first.
mkdir -p "$APP/Contents/Resources/Fonts"
cp Sources/Murmur/Resources/Fonts/*.ttf "$APP/Contents/Resources/Fonts/"

# App icon (source: Resources/Murmur.svg — rerun scripts/make_icon.sh to
# regenerate Resources/Murmur.icns after changing the SVG).
if [ -f "Resources/Murmur.icns" ]; then
    cp Resources/Murmur.icns "$APP/Contents/Resources/Murmur.icns"
fi

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>local.murmur</string>
    <key>CFBundleName</key>
    <string>Murmur</string>
    <key>CFBundleExecutable</key>
    <string>Murmur</string>
    <key>CFBundleIconFile</key>
    <string>Murmur</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>2.1.0</string>
    <key>CFBundleVersion</key>
    <string>4.3</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Murmur records your voice while you hold the dictation key so it can transcribe it on-device.</string>
    <key>NSHumanReadableCopyright</key>
    <string>Local build — no data leaves this Mac.</string>
</dict>
</plist>
PLIST

# The stable local identity is what keeps macOS permission grants valid
# across rebuilds: TCC stores a code requirement at the moment you grant
# Microphone/Accessibility, then re-validates every launch. A self-signed
# certificate pins that requirement to the certificate, which survives
# rebuilds. An ad-hoc signature (-) pins it to the binary's cdhash, which
# changes on EVERY build — so macOS stops recognising the app and asks for
# permission again each time.
#
# Ad-hoc is therefore a hard failure, not a silent fallback: one ad-hoc
# build is enough to invalidate a grant recorded against the certificate.
if security find-identity -v -p codesigning 2>/dev/null | grep -q "WhisperFlow Dev"; then
    codesign --force --sign "WhisperFlow Dev" "$APP"
    echo "Signed with 'WhisperFlow Dev'."
else
    echo "ERROR: signing identity 'WhisperFlow Dev' not found." >&2
    echo "Run scripts/make_signing_cert.sh first — signing ad-hoc would make macOS" >&2
    echo "re-prompt for Microphone and Accessibility on every single rebuild." >&2
    exit 1
fi

echo "Built $APP"
