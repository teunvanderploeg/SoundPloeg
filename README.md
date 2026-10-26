# SoundPloeg

A local macOS menu bar app that reads clipboard text aloud in English and Dutch.

This is a beta release. The shared Ploeg interface and Toolbox integration are
still being refined; updates and fixes will follow.

- Kokoro v1.0: Heart, Michael, Emma, and George. One 328 MB English pack.
- Supertonic 3: Dutch Female and Dutch Male. One 399 MB Dutch pack.
- Persistent CPU speech worker, with the next text chunk prepared during playback.
- Offline speech after installation. No account, API key, or cloud synthesis.
- macOS voice fallback, queue controls, global hotkey, and recent speech history.

The menu bar panel shows the current reading, voice, completed parts, and waiting
items. Errors and confirmations appear in the panel and Settings and can be
dismissed. Clipboard readings retain the full text, including readings longer
than 4,000 characters. History supports search, full-text viewing, copying,
individual deletion, and replay with the original voice/rate or current settings.

## Use from Codex or Terminal

Generate local narration and podcasts with `soundploeg speak` and `soundploeg podcast`.
A personal Codex skill and optional local MCP server let you ask, "Use SoundPloeg
to turn this summary into a podcast." See [agent and CLI setup](Docs/AgentSpeech.md).

## Setup

Requires macOS 13+, Xcode, Python 3.10–3.13, and XcodeGen for the app bundle.
The shared SwiftUI package must be checked out beside this repository at
`../PloegKit`. It supplies the Ploeg colors, components and generated app icons.

Use this source layout:

```text
PloegApps/
├── PloegKit/      # v0.1.0-beta.1
└── SoundPloeg/
```

From the directory containing your SoundPloeg checkout, clone the matching
PloegKit beta tag before building:

```bash
git clone --branch v0.1.0-beta.1 https://github.com/teunvanderploeg/PloegKit.git PloegKit
cd SoundPloeg
```

Both Swift Package Manager and the Xcode project use this local sibling package.

```bash
./Scripts/bootstrap_tts.sh
swift test
./Scripts/generate_xcodeproj.sh
open SoundPloeg.xcodeproj
```

Build and run the `SoundPloegApp` scheme, or use `swift run SoundPloeg`.
Open Settings → Models to select a voice. Each pack downloads all its voices;
removing a pack removes all voices in that pack.

The installer creates `~/Library/Application Support/SoundPloeg/tts-venv` and
installs both packs into its `models` directory. Downloads use pinned revisions,
expected sizes, and SHA-256 hashes. Existing packs are verified before reuse.
The installer removes known old Piper model files only after both new packs are
installed. It preserves speech history and unrelated/custom model files.
The app no longer scans or runs Piper models.

To use another Python or installation location, set `SOUNDPLOEG_PYTHON`,
`SOUNDPLOEG_SUPPORT_DIR`, and/or `SOUNDPLOEG_MODEL_DIR`. When using a custom model
root in app settings, pass that same directory as `SOUNDPLOEG_MODEL_DIR` during
setup. The app runtime location remains the standard Application Support path.

## Interface previews

The native interface follows macOS appearance and the shared Ploeg design.
These optional preview modes use in-memory settings and example content, skip
hotkey registration and speech startup, and disable action controls:

```bash
swift run SoundPloeg --design-preview
swift run SoundPloeg --design-preview-menu
```

The first opens Settings with working navigation; the second displays the compact
menu panel in a window. Neither reads the clipboard or saved reading history.

## Open from PloegToolbox

The app accepts `--show-settings` on a cold launch. A standard macOS reopen event
also brings Settings forward when SoundPloeg is already running. Both routes,
the menu panel's Settings button and Command-comma reuse one settings window.
Opening the app does not read the clipboard or queue speech.

The built bundle advertises `PloegToolboxOpenVersion = 1`. Preview launch flags
and review-bundle preview metadata keep their isolated behavior on reopen.

## Verification

```bash
./Scripts/release_preflight.sh
"$HOME/Library/Application Support/SoundPloeg/tts-venv/bin/python" \
  Scripts/smoke_tts.py \
  --root "$HOME/Library/Application Support/SoundPloeg/models"
```

After building an app bundle, check its icon declaration and metadata before installing:

```bash
./Scripts/verify_app_bundle.sh /path/to/SoundPloeg.app
```

The smoke check synthesizes every voice twice in one worker, checks the WAVs,
and reports generation time versus audio duration. It does not use system voice
fallback, so failures cannot be hidden by a macOS voice.

For Swift integration tests with real inference, set
`SOUNDPLOEG_TEST_MODEL_ROOT` and `SOUNDPLOEG_TEST_PYTHON` before `swift test`.
Without those variables, only that optional real-model test is skipped.

## Backend choices

Kokoro FP32 was faster than the smaller INT8 export in our local CPU checks.
The FP16 export produced invalid audio for Michael, so it is not shipped.
The four English voices share one model, rather than downloading separate
weights for each voice. Supertonic supplies native Dutch inference; its larger
pack is a quality/language-support tradeoff, not a size reduction over Piper.
Neither engine needs a GPU.

Supertonic's upstream was archived in September 2026. Its inference helper is
vendored with its MIT license, and its weights are pinned to an immutable
revision. Model weights have their own licenses. See [third-party notices](Docs/ThirdParty.md).

## Troubleshooting

If local speech fails, Diagnostics shows the underlying error and the app falls
back to a macOS voice of the same language when available. Run the bootstrap
script to repair missing runtime packages or damaged models. Model downloads
in Settings are staged and checked before becoming available.

Stop and Skip cancel pending local generation. Stop also unloads the worker;
the next request loads its model again. Long text retains punctuation and is
split at sentence or word boundaries. Single-chunk jobs keep exportable WAVs
for the three most recent history entries.

## Keyboard shortcuts

The configured global shortcut, initially **⌘⇧S**, reads clipboard text from
any app. With Auto-speak turned off, it queues the text instead. Change it in
Settings → Playback. Press Escape to cancel recording a new shortcut.
Use **Play Queue** to start waiting readings without reading the clipboard again.

These shortcuts work when SoundPloeg is active and are shown in its menus and
in Settings → Overview and Playback:

| Action | Shortcut |
|---|---|
| Speak clipboard | ⌘↩ |
| Play waiting queue | ⌥⌘↩ |
| Pause / resume | ⌥⌘P |
| Stop | ⌘. |
| Skip current item | ⌥⌘→ |
| Clear waiting queue | ⌥⌘⌫ |
| Settings | ⌘, |
| Quit | ⌘Q |
