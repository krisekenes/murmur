#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Debug builds need a STABLE code signature, not just any signature.
#
# macOS records Accessibility and Microphone grants against a code signing
# requirement. A properly signed app is identified by bundle id + team id, which
# survives a rebuild. An ad-hoc binary has no such identity, so TCC falls back to
# the cdhash — which changes every time the binary is recompiled, so macOS treats
# each rebuild as a brand new app and asks for both permissions again.
#
# Hence: never pass CODE_SIGNING_ALLOWED=NO here. That flag belongs only in
# package-release.sh, which re-signs explicitly afterwards.
#
# The team id is read from your Apple Development certificate so nothing
# personal is committed. Override with MURMUR_DEVELOPMENT_TEAM if you have more
# than one.

command -v xcodegen >/dev/null || { echo 'Install XcodeGen first (brew install xcodegen).' >&2; exit 1; }

detect_team() {
  security find-certificate -c 'Apple Development' -p 2>/dev/null \
    | openssl x509 -noout -subject -nameopt multiline 2>/dev/null \
    | sed -n 's/.*organizationalUnitName *= *//p' | head -1
}
team="${MURMUR_DEVELOPMENT_TEAM:-$(detect_team)}"

xcodegen generate

args=(-project Murmur.xcodeproj -scheme Murmur -configuration Debug
      -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/debug
      -disableAutomaticPackageResolution -skipMacroValidation)

if [[ -n "$team" ]]; then
  args+=(DEVELOPMENT_TEAM="$team" CODE_SIGN_STYLE=Automatic)
else
  echo 'No Apple Development certificate found, and MURMUR_DEVELOPMENT_TEAM is unset.' >&2
  echo 'Falling back to an ad-hoc build: macOS will re-ask for Accessibility and' >&2
  echo 'Microphone after every rebuild. See docs/RELEASING.md.' >&2
  args+=(CODE_SIGNING_ALLOWED=NO)
fi

xcodebuild "${args[@]}" build

app='.build/debug/Build/Products/Debug/Murmur.app'
# Print the identity the grants will be pinned to, so a silent fallback to
# ad-hoc is visible rather than discovered later through a permission prompt.
echo
echo 'Signed as:'
codesign -dvv "$app" 2>&1 | grep -E 'Identifier=|TeamIdentifier=|Signature=' || true
echo
echo "Built $app"
