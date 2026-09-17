# Murmur

Local dictation for your Mac. Hold a hotkey, speak, and release to insert text into the app you're using. Murmur lives in the menu bar and includes optional AI cleanup, a dictation history, and a scratchpad notebook.

## Download and install

Requires an **Apple Silicon Mac (M1 or later), macOS 14 or later**, and an internet connection for the initial model downloads. Intel Macs, Windows, and Linux are not supported. Allow several GB of free storage for models. Speech recognition uses the English Parakeet v2 model.

1. Open the [Releases page](https://github.com/krisekenes/murmur/releases) and download `Murmur-<version>-macOS-arm64.zip` from the release assets. GitHub's “Source code” ZIP is for developers; it isn't an app. If no release is available yet, use the build instructions below.
2. Unzip it and drag **Murmur.app** into **Applications** before opening it.
3. Open Terminal and run this command, then open Murmur:

   ```bash
   xattr -dr com.apple.quarantine /Applications/Murmur.app
   ```

   Preview builds aren't notarized by Apple yet, so without this step macOS reports “Murmur” Not Opened and offers only Move to Trash. The command removes the quarantine flag your browser added to this download; it affects only Murmur. Repeat it after installing each new version. To avoid Terminal, try opening Murmur once, then click **Open Anyway** in System Settings → Privacy & Security ([Apple's instructions](https://support.apple.com/en-us/102445)). A managed Mac may block both methods.
4. Grant Microphone and Accessibility access when prompted. If your hotkey still doesn't work, check Input Monitoring in System Settings → Privacy & Security and restart Murmur.
5. Wait for model preparation to finish. First launch downloads the speech and polish models and can take several minutes. Later launches reuse the cached models.

## Use

- **Hold Fn/Globe**, speak, then release to transcribe.
- **Double-tap** to keep recording hands-free; tap again to finish.
- **Escape** cancels recording.
- Choose **Right Option** instead in Settings. For Fn, set System Settings → Keyboard → “Press Globe key to” → “Do Nothing”.
- Toggle **Polish with AI** to clean up wording. Short utterances and unavailable/timed-out polish use the raw transcript. Vocabulary entries guide polishing, not speech recognition.
- Click **Smart organize** above the conversation feed to preview folder suggestions for all unfiled conversations. It matches existing folder names and tags from previously filed conversations, then suggests topic folders. Edit destinations or deselect items before applying; **Undo moves** reverses the latest batch during the current session, leaving created folders available.
- Conversations receive local topic tags automatically, including existing history. Search conversation text or tags in the top bar, filter by folder or tag above the feed, and select a conversation to move it or edit its tags. Short or unrecognized text may have no automatic tags.
- In the scratchpad, use Browse to search notes and filter by folder or tag. Use the folder menu to move a note or manage folders; deleting a folder keeps its notes in Unfiled.
- Add custom tags or click a suggested tag to accept it. Suggestions use local keyword matching, hashtags, and your existing tags; they update as you type or dictate and require no model download. Click an assigned tag’s × to remove it.
- Open Murmur from its menu-bar icon to browse dictations and notes. Click a recent dictation in the menu to copy it.

Wait until processing finishes before starting another dictation. If you switch apps during processing, Murmur puts the result on the clipboard instead of pasting into the new app. Results are also kept in history. AI cleanup can change meaning; review important text.

## Privacy and storage

Murmur processes recorded audio and text locally, with no account or API key. Audio is held in memory and is not saved to disk. Model downloads contact the model hosts; first use is not offline. Models are downloaded separately and aren't bundled in the app ZIP.

The latest 200 dictations (raw and polished), vocabulary, and scratchpad pages are stored as **unencrypted local files** under `~/Library/Application Support/Murmur/`. Preferences use macOS UserDefaults. Model caches are managed separately by FluidAudio and Hugging Face. Clipboard insertion can be visible to clipboard managers. Quit Murmur before manually backing up or removing its data directory.

## Future development

Planned improvements, in priority order (not available in the current preview):

- **Microphone selection:** choose an input device in Settings and check its input level before dictating.
- **Optional model downloads:** use speech recognition on its own and download the AI cleanup model only when needed, with clearer download sizes and cache controls.
- **History retention controls:** choose how much dictation history to keep, disable saved history, and clear stored transcripts from the app.
- **Optional audio preview:** review a recording before transcription or insertion, with explicit controls for discarding it.

Before a stable release, complete Developer ID signing, notarization, and installation testing on a fresh Mac. These plans may change as friends try the preview and share feedback; no release dates are committed.

## Build from source

Use an Apple Silicon Mac with **Xcode 26.3** (the tested toolchain), its command-line tools, and [XcodeGen](https://github.com/yonaskolb/XcodeGen). Install XcodeGen with `brew install xcodegen` if needed.

```sh
git clone https://github.com/krisekenes/murmur.git
cd murmur
bash tools/package-release.sh
```

This runs tests, generates the Xcode project, builds Release, collects dependency notices, ad-hoc signs the app, and creates a ZIP plus SHA-256 checksum under `release/`. It downloads the existing pinned build dependencies. The build explicitly enables their Swift macros with `-skipMacroValidation`; only build dependency revisions you trust.

For development, run `xcodegen generate`, open `Murmur.xcodeproj`, and select the Murmur scheme. Approve the MLX macro if Xcode asks. Test the standalone core with `swift test --package-path MurmurCore`.

Run `bash tools/check-beta-state.sh` for beta state regression checks with isolated temporary data. These checks cover delayed folder naming, manual edits, undo, page merges, and live conversation details, and also run during release packaging.

`project.yml` is the project source of truth. The generated Xcode project is ignored, except for the committed `Package.resolved` dependency pins. Regenerate after changing project settings.

See [release instructions](docs/RELEASING.md) for signing, notarization, and GitHub uploads, and [third-party notices](THIRD_PARTY_NOTICES.md) for model attribution.

Murmur's source code is available under the [MIT license](LICENSE).
