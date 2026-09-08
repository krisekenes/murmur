# Publishing Murmur

## Build a preview

Run `bash tools/package-release.sh` from the repository root. Outputs appear in `release/`; build products and user data must not be committed. The default archive is ad-hoc signed and **not notarized**. GitHub Actions produces the same preview artifact on pushes, pull requests, and manual runs; it does not publish releases.

Set `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml` before a release. The generated Info.plist derives its version from those settings. Keep the existing `Murmur.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` in Git so fresh builds use the tested dependency revisions.

## Sign and notarize for friends

Use your Apple Developer ID Application certificate and a notarytool keychain profile configured with your Apple developer credentials. Keep certificates and credentials outside this repository.

```sh
MURMUR_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
MURMUR_NOTARY_PROFILE='murmur-notary' \
bash tools/package-release.sh
```

The script signs with the hardened runtime and microphone entitlement, submits the ZIP to Apple's notary service, staples the accepted ticket, verifies it, and rebuilds the ZIP and checksum. Notarization is opt-in and uploads the application to Apple. See [Apple's notarization documentation](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

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
