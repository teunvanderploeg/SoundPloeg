# SoundPloeg

A local macOS menu bar app that reads clipboard text aloud in English and Dutch.

- Kokoro v1.0: Heart, Michael, Emma, and George. One 328 MB English pack.
- Supertonic 3: Dutch Female and Dutch Male. One 399 MB Dutch pack.
- Persistent CPU speech worker, with the next text chunk prepared during playback.
- Offline speech after installation. No account, API key, or cloud synthesis.
- macOS voice fallback, queue controls, global hotkey, and recent speech history.

## Setup

Requires macOS 13+, Xcode, Python 3.10–3.13, and XcodeGen for the app bundle.

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

These shortcuts work when SoundPloeg is active and are shown in its menus and
in Settings → Overview and Playback:

| Action | Shortcut |
|---|---|
| Speak clipboard | ⌘↩ |
| Pause / resume | ⌥⌘P |
| Stop | ⌘. |
| Skip current item | ⌥⌘→ |
| Clear waiting queue | ⌥⌘⌫ |
| Settings | ⌘, |
| Quit | ⌘Q |
