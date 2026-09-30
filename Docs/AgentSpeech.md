# Use SoundPloeg from Codex or Terminal

SoundPloeg renders narration and podcasts locally using the same installed models as the menu bar app. Codex writes the spoken script and chooses voices. The app can be closed. Nothing is uploaded or published.

## Install on this Mac

After the normal TTS bootstrap:

```bash
"$HOME/Library/Application Support/SoundPloeg/tts-venv/bin/python" Scripts/install_agent_tools.py --mcp
```

This installs `~/.local/bin/soundploeg`, a personal `soundploeg` skill under `${CODEX_HOME:-~/.codex}/skills`, and a local stdio MCP server registered with `codex mcp add`. MCP dependencies live in a separate `mcp-venv` beside `tts-venv`. Omit `--mcp` to install only the command and skill. Keep this repository checkout in place; the command links to it. Include `~/.local/bin` in your shell PATH to use the short command.

Start a new Codex task, or restart Codex if it has not picked up the additions. Ask:

> Use SoundPloeg to turn this summary into a five-minute English podcast with Heart and Michael. Save the script and an MP3 in this task.

Explicit skill invocation also works: `$soundploeg`. SoundPloeg is the local renderer, not the SoundCloud publishing service. Duration depends on the script, voice, and rate; requested length is approximate.

## Terminal commands

```bash
soundploeg doctor
soundploeg voices
soundploeg speak summary.txt --voice Heart --output summary.mp3
soundploeg speak --text 'Goedemorgen!' --voice 'Dutch Female' --output dutch.wav
cat summary.txt | soundploeg speak - --output summary.wav
soundploeg podcast episode.json --output episode.mp3
```

`speak` reads text verbatim; it does not summarize, remove Markdown, or write a podcast script. The agent does that before rendering. WAV works with the installed speech packages. MP3 needs ffmpeg, as does mixing Kokoro and Supertonic in one recording. The CLI looks on PATH and in the usual Homebrew locations for ffmpeg.

Episode JSON:

```json
{
  "speakers": {"host": "Heart", "guest": "Michael"},
  "segments": [
    {"speaker": "host", "text": "Welcome to our weekly update."},
    {"speaker": "guest", "text": "Here is what changed.", "rate": 1.0, "pause_after": 0.5}
  ]
}
```

Segments accept `voice` instead of a named `speaker`. Voice names are case-insensitive; full IDs from `voices` also work. Rate ranges from 0.5 to 2.0; pauses from 0 to 10 seconds. Text is split at sentence or word boundaries into small requests and synthesized by one persistent worker for the recording. The resulting audio is joined with pauses and written atomically. Existing outputs are protected unless the CLI receives `--overwrite`.

Progress goes to stderr. Successful CLI stdout is JSON with `output`, `duration` in seconds, `chunks`, and `voices`. Errors produce a nonzero exit status. The renderer times out after 120 seconds without a worker reply for one chunk. Each recording loads its own worker and releases it when finished.

## MCP tools

The server uses stdin/stdout and opens no network port:

- `list_voices`: installed voices and languages.
- `synthesize_speech`: text, voice, rate, and absolute output filename.
- `render_podcast`: episode object and absolute output filename.
- `get_job`: progress and final result for a returned job ID.

Rendering tools return immediately with a job ID. Poll until `completed` or `failed` before reporting a result. One recording runs at a time, with at most four pending jobs. Job metadata belongs to the server session; it is not a durable queue. Finished audio remains on disk. Keep Codex open while rendering. The server never overwrites existing audio. Files are created with the local user's filesystem permissions, so agents should use their task's output directory.

To remove the MCP registration, run `codex mcp remove soundploeg`. The CLI symlink and personal skill can be removed independently. The app and model installation do not depend on them.

Configuration follows `SOUNDPLOEG_SUPPORT_DIR`, `SOUNDPLOEG_MODEL_DIR`, and `SOUNDPLOEG_PYTHON`. Set these in the MCP server environment too if using a custom installation.

## Verification

```bash
python3 -m unittest discover -s Tests/Python -v
"$HOME/Library/Application Support/SoundPloeg/mcp-venv/bin/python" Scripts/smoke_agent_tools.py
```

The smoke check exercises actual CLI narration and two-voice rendering, then initializes an MCP client, discovers tools, and waits for a real speech job to finish. It writes test audio to a temporary directory and removes it afterwards.
