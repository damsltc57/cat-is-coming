#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir "$scratch/cache"
xcrun swiftc -swift-version 6 -module-cache-path "$scratch/cache" \
    Sources/InputFilter.swift Sources/KeyboardActivity.swift Sources/PawDetector.swift \
    Tests/AutomaticPawLockTests.swift -o "$scratch/paw-lock-tests"
"$scratch/paw-lock-tests"
