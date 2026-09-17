#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

command -v xcodegen >/dev/null || { echo 'Install XcodeGen first (brew install xcodegen).' >&2; exit 1; }
swift test --package-path MurmurCore
bash tools/check-beta-state.sh
xcodegen generate
xcodebuild -project Murmur.xcodeproj -scheme Murmur -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/release \
  -disableAutomaticPackageResolution -skipMacroValidation CODE_SIGNING_ALLOWED=NO build

app='.build/release/Build/Products/Release/Murmur.app'
python3 tools/collect-licenses.py "$app/Contents/Resources/ThirdPartyLicenses"
cp THIRD_PARTY_NOTICES.md "$app/Contents/Resources/"
if [[ -f LICENSE ]]; then cp LICENSE "$app/Contents/Resources/Murmur-LICENSE.txt"; fi

# Ad-hoc signing supports local testing. Developer ID signing is opt-in.
identity="${MURMUR_SIGNING_IDENTITY:--}"
if [[ "$identity" == '-' ]]; then
  codesign --force --deep --sign - "$app"
else
  codesign --force --deep --options runtime --timestamp \
    --entitlements App/Murmur.entitlements --sign "$identity" "$app"
fi
codesign --verify --deep --strict "$app"

version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")
mkdir -p release
archive="release/Murmur-${version}-macOS-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
if [[ -n "${MURMUR_NOTARY_PROFILE:-}" ]]; then
  [[ "$identity" != '-' ]] || { echo 'Notarization requires a Developer ID identity.' >&2; exit 1; }
  xcrun notarytool submit "$archive" --keychain-profile "$MURMUR_NOTARY_PROFILE" --wait
  xcrun stapler staple "$app"
  xcrun stapler validate "$app"
  spctl --assess --type execute --verbose "$app"
  ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
fi
(cd release && shasum -a 256 "$(basename "$archive")" > "$(basename "$archive").sha256")
echo "Created $archive"
if [[ -z "${MURMUR_NOTARY_PROFILE:-}" ]]; then
  echo 'This build is NOT notarized. See docs/RELEASING.md before sharing.'
fi
