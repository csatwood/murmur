#!/bin/bash
# Runs source-level regression tests against the actual vendored Harper archive.
# Optional first argument: path to an installed macOS SDK.
set -euo pipefail
cd "$(dirname "$0")/.."
CORRECTIONS_SDK="${1:-$(xcrun --sdk macosx --show-sdk-path)}"
CORRECTIONS_TMP="$(mktemp -d)"
trap 'rm -rf "$CORRECTIONS_TMP"' EXIT
swiftc -O -sdk "$CORRECTIONS_SDK" \
    -F Vendor/harper.xcframework/macos-arm64 -framework harper \
    Sources/Murmur/TextFormatter.swift Sources/Murmur/LearnedStore.swift \
    Sources/Murmur/HarperChecker.swift Tests/CorrectionsHarness.swift \
    -o "$CORRECTIONS_TMP/corrections-tests"
"$CORRECTIONS_TMP/corrections-tests"
