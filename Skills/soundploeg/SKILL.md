---
name: soundploeg
description: Generate local speech, narrated summaries, and podcasts with SoundPloeg using Kokoro English or Supertonic Dutch voices. Use when the user asks to use SoundPloeg, local TTS, or turn provided text into an audio recording. Does not upload or publish to SoundCloud.
---

# SoundPloeg

Use the installed SoundPloeg models on this Mac. Speech generation is offline and does not need the menu bar app. Codex writes the script; SoundPloeg renders it.

## Create the recording

For a request to read text, preserve the text. For a podcast request, adapt the supplied material into spoken language while preserving facts and uncertainty. Use one narrator unless a conversation is requested or clearly useful. Do not invent claims or quotations to fill time. Roughly 130–160 spoken words per minute is a planning estimate, not a duration guarantee.

List available voices first. Heart and Michael are useful English defaults; Dutch Female and Dutch Male use Supertonic. Save a readable script beside the audio. A two-speaker episode uses this JSON structure:

```json
{
  "speakers": {"host": "Heart", "guest": "Michael"},
  "segments": [
    {"speaker": "host", "text": "Welcome. Here is today's summary."},
    {"speaker": "guest", "text": "Let's explain what changed.", "pause_after": 0.5}
  ]
}
```

Each segment accepts either `speaker` or `voice`, `text`, optional `rate` from 0.5 to 2.0, and `pause_after` from 0 to 10 seconds. Long text is split automatically. Prefer MP3 for a podcast; WAV works without ffmpeg for a single engine. English/Dutch mixed episodes require ffmpeg too.

## Use the local tools

When SoundPloeg MCP tools are available, use `list_voices`, then `synthesize_speech` or `render_podcast`. Supply an absolute output path in the current task's writable output directory. These tools return a job ID, not finished audio. Poll `get_job` every few seconds until `completed` or `failed`; do not report success based on job creation. Jobs are session-local; keep the task active until completion.

Otherwise use the CLI. The installer replaces `@SOUNDPLOEG_COMMAND@` below with the absolute command path on this Mac. In a repository checkout before installation, use `Scripts/soundploeg`.

```bash
"@SOUNDPLOEG_COMMAND@" voices
"@SOUNDPLOEG_COMMAND@" speak /absolute/path/summary.txt --voice Heart --output /absolute/path/summary.mp3
"@SOUNDPLOEG_COMMAND@" podcast /absolute/path/episode.json --output /absolute/path/episode.mp3
```

Write source text or episode JSON to a file rather than interpolating it into shell commands. CLI stdout is JSON; stderr carries progress. Check the exit code and final `output` path. Existing audio is protected; choose a new filename unless the user wants it replaced. `--overwrite` is available on the CLI.

Return the audio using `![Podcast](/absolute/path/episode.mp3)` and link the saved script. Do not automatically play aloud or upload the file unless requested. If rendering fails, show the actual error. `soundploeg doctor` checks the installation; do not silently switch to a cloud TTS service.
