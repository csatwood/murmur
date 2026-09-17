#!/bin/bash
# Wraps build/Murmur.app (built by make_app.sh) into a distributable .dmg,
# plus a .zip of the same build for the in-app updater (AppInstaller.swift)
# to consume — attach BOTH to the GitHub release, or in-app auto-update
# silently falls back to the manual .dmg link for that version.
#
# This is a self-signed build, not a notarized one — Gatekeeper will still
# tell anyone who downloads the .dmg by hand that it's from an unidentified
# developer (System Settings -> Privacy & Security -> Open Anyway gets past
# it, once, per Mac). The in-app updater sidesteps this entirely: a plain
# URLSession download never sets the quarantine flag Gatekeeper checks, so
# an update installed through the app never hits that prompt — only a
# from-scratch manual download does.
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

# The versioned name is what ships as a GitHub release asset, so old
# versions stay individually downloadable. This unversioned copy is what
# murmurmac.com's DOWNLOAD_LINK actually points at, via GitHub's
# releases/latest/download/ permalink — that URL only ever resolves a
# fixed filename against whatever release is currently "latest", so it
# needs a name that doesn't change release to release. Without this, every
# release would need a matching manual update to the site's env var.
UNVERSIONED="build/Murmur.dmg"
cp -f "$DMG" "$UNVERSIONED"

# `ditto -c -k` (not plain `zip`) preserves the code signature and
# extended attributes correctly — required for AppInstaller's Bundle(url:)
# bundle-identifier check to see a validly-signed app after unzipping.
ZIP="build/Murmur-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent build/Murmur.app "$ZIP"

echo "Built $DMG, $UNVERSIONED, and $ZIP"
echo "Attach both $DMG and $ZIP to the GitHub release for this version."
