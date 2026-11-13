#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir "$scratch/cache"
xcrun swiftc -swift-version 6 -module-cache-path "$scratch/cache" \
    Sources/FirstLaunchSetup.swift Tests/FirstLaunchSetupTests.swift -o "$scratch/first-launch-tests"
"$scratch/first-launch-tests"
