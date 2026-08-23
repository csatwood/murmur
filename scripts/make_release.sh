#!/bin/bash
# Wraps build/Murmur.app (built by make_app.sh) into a distributable .dmg.
#
# This is a self-signed build, not a notarized one — Gatekeeper will still
# tell anyone who downloads it that it's from an unidentified developer.
# That's expected for now: right-click the app -> Open (or System Settings
# -> Privacy & Security -> Open Anyway) gets past it, once, per Mac.
set -euo pipefail

cd "$(dirname "$0")/.."

./scripts/make_app.sh

VERSION=$(defaults read "$(pwd)/build/Murmur.app/Contents/Info" CFBundleShortVersionString)
DMG="build/Murmur-$VERSION.dmg"

STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT

cp -R build/Murmur.app "$STAGING/"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG"
hdiutil create -volname Murmur -srcfolder "$STAGING" -ov -format UDZO "$DMG"

echo "Built $DMG"
