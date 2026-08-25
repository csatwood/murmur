#!/bin/bash
# Builds Murmur.app from the SwiftPM release binary.
set -euo pipefail

cd "$(dirname "$0")/.."

swift build -c release

APP="build/Murmur.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/Murmur "$APP/Contents/MacOS/Murmur"

# Bundled fonts: copied straight into Contents/Resources rather than
# SwiftPM's generated Murmur_Murmur.bundle, which it expects at the .app's
# top level — codesign won't seal resources living outside Contents/, and
# fails to verify. FontLoader checks Bundle.main (this location) first.
if [ -d ".build/release/Murmur_Murmur.bundle/Fonts" ]; then
    mkdir -p "$APP/Contents/Resources/Fonts"
    cp .build/release/Murmur_Murmur.bundle/Fonts/*.ttf "$APP/Contents/Resources/Fonts/"
fi

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
    <string>2.0.1</string>
    <key>CFBundleVersion</key>
    <string>3</string>
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
