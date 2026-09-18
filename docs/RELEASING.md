# Publishing Murmur

## Build a preview

Run `bash tools/package-release.sh --preview` from the repository root for local testing. Outputs appear in `release/` with an explicit `-unnotarized-preview` filename suffix; build products and user data must not be committed. Preview archives are ad-hoc signed and **not notarized**. Their signing identity changes with each build and can invalidate saved macOS permissions. GitHub Actions produces only these test artifacts; it does not publish releases. Do not use them as routine updates for friends.

Without `--preview`, packaging requires a Developer ID Application signing identity and a notarization profile before building. Missing configuration stops the script instead of silently producing an ad-hoc release. `--check-config` validates configuration without building or using credentials; it does not verify that the certificate or notary profile exists.

Set `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml` before a release. The generated Info.plist derives its version from those settings. Keep the existing `Murmur.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` in Git so fresh builds use the tested dependency revisions.

## Sign and notarize for friends

Use your Apple Developer ID Application certificate and a notarytool keychain profile configured with your Apple developer credentials. Keep certificates and credentials outside this repository.

```sh
MURMUR_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
MURMUR_NOTARY_PROFILE='murmur-notary' \
bash tools/package-release.sh
```

The distribution script signs with the hardened runtime and microphone entitlement, submits the ZIP to Apple's notary service, staples the accepted ticket, verifies it, and rebuilds the ZIP and checksum. Running distribution packaging uploads the application to Apple; `--preview` never submits it. See [Apple's notarization documentation](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

### Keep permission grants across updates

Enroll in the [Apple Developer Program](https://developer.apple.com/programs/enroll/), create a **Developer ID Application** certificate in Xcode's account settings or the developer portal, and configure a notarytool keychain profile. Keep credentials in Keychain, not this repository or chat. An Apple Development certificate is for local development and is not a substitute for Developer ID distribution signing.

Keep the distribution bundle identifier (`com.murmur.Murmur`) and Developer ID team consistent. macOS recognizes updates through their designated signing requirement, not just the displayed app name. Confirm it with `codesign -d -r- /Applications/Murmur.app`; a distribution build must not have a requirement consisting only of a `cdhash`. See [Apple TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements).

Users moving from the old ad-hoc previews may need a final permission regrant. Validate the fix by granting permissions to one Developer ID-signed build, replacing it with a second signed build from the same team, and confirming microphone access, hotkey detection, and paste work without removing any System Settings entries. Test development and distribution builds separately: their default signing requirements differ. Notarization improves installation trust; stable code identity is what addresses update recognition.

## Check the actual download

Before making the release public, test the archived app on a second Apple Silicon Mac or a fresh macOS user account:

- Install in Applications; confirm version, icon, and menu-bar behavior.
- Complete first-run permissions and model downloads; relaunch with cached models.
- Dictate into TextEdit and a browser, with AI cleanup both on and off.
- Try hold, double-tap, Escape, and switching hotkeys in Settings.
- Switch apps during processing; confirm text is copied rather than pasted into the new app.
- Confirm clipboard restoration, history, vocabulary, notes, and launch at login.
- Check missing/revoked microphone permissions and a failed model download. Use “Retry model loading” in the menu or main window.

Automated tests and compilation do not verify microphone access, model inference, Gatekeeper, or text insertion on another Mac. Signing/notarization and this manual acceptance pass must be completed for a polished public release.

## Upload to GitHub

Create the repository and push the reviewed source, including the dependency pins. Create a draft release with a version tag matching `project.yml`; attach the ZIP and its `.sha256` file from `release/`. Clearly label any unnotarized release as a preview. Publish after the installation checks pass. Friends should download the app asset, not the auto-generated source archive.
