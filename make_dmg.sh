#!/bin/bash
#
# Builds a universal Release of Spidercal and packages it as
# build/Spidercal.dmg, ready to attach to a GitHub release.
#
# The app is signed for local use only (see Local.xcconfig.example).
# It isn't notarized, so macOS blocks it on first open: see the README.

set -euo pipefail
cd "$(dirname "$0")"

[ -f Local.xcconfig ] || cp Local.xcconfig.example Local.xcconfig

xcodebuild -quiet \
    -project Itsycal.xcodeproj \
    -scheme Itsycal \
    -configuration Release \
    -derivedDataPath build \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    build

STAGING=build/dmg
rm -rf "$STAGING" build/Spidercal.dmg
mkdir -p "$STAGING/Licenses"
ditto build/Build/Products/Release/Spidercal.app "$STAGING/Spidercal.app"
ln -s /Applications "$STAGING/Applications"
cp LICENSE.txt "$STAGING/Licenses/Spidercal and Itsycal.txt"
cp ThirdPartyLicenses/MASShortcut.txt "$STAGING/Licenses/MASShortcut.txt"

hdiutil create -quiet \
    -volname Spidercal \
    -srcfolder "$STAGING" \
    -format UDZO \
    build/Spidercal.dmg

echo "Created build/Spidercal.dmg"
