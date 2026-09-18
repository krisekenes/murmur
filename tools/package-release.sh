#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

preview=false
check_config=false
for argument in "$@"; do
  case "$argument" in
    --preview) preview=true ;;
    --check-config) check_config=true ;;
    *) echo "Usage: $0 [--preview] [--check-config]" >&2; exit 1 ;;
  esac
done

# Public releases need a consistent identity. Never silently produce an ad-hoc
# download: its cdhash identity changes on every build, invalidating TCC grants.
identity="${MURMUR_SIGNING_IDENTITY:-}"
if "$preview"; then
  if [[ -n "$identity" || -n "${MURMUR_NOTARY_PROFILE:-}" ]]; then
    echo 'Do not combine --preview with signing or notarization credentials.' >&2
    exit 1
  fi
  identity='-'
else
  case "$identity" in
    'Developer ID Application: '*) ;;
    *) echo 'Distribution requires MURMUR_SIGNING_IDENTITY set to a Developer ID Application certificate. Use --preview only for local/CI testing.' >&2; exit 1 ;;
  esac
  if [[ -z "${MURMUR_NOTARY_PROFILE:-}" ]]; then
    echo 'Distribution requires MURMUR_NOTARY_PROFILE. See docs/RELEASING.md.' >&2
    exit 1
  fi
fi
if "$check_config"; then
  echo 'Release configuration is valid (certificate and notary credentials are checked during packaging).'
  exit 0
fi

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

# Ad-hoc signing is available only through the explicit local/CI preview mode.
if [[ "$identity" == '-' ]]; then
  codesign --force --deep --sign - "$app"
else
  codesign --force --deep --options runtime --timestamp \
    --entitlements App/Murmur.entitlements --sign "$identity" "$app"
fi
codesign --verify --deep --strict "$app"

version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")
mkdir -p release
suffix=''
if "$preview"; then suffix='-unnotarized-preview'; fi
archive="release/Murmur-${version}-macOS-arm64${suffix}.zip"
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
