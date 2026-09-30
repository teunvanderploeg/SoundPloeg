"""Local speech rendering shared by the CLI and MCP server."""
import argparse
import json
import math
import os
from pathlib import Path
import re
import selectors
import shutil
import subprocess
import sys
import tempfile
import uuid
import wave

WORKER = Path(__file__).resolve().parents[1] / 'Sources/SoundPloegInfra/Resources/Runtime/tts_worker.py'


def support_root():
    return Path(os.environ.get('SOUNDPLOEG_SUPPORT_DIR', Path.home() / 'Library/Application Support/SoundPloeg'))


def speech_python():
    return os.environ.get('SOUNDPLOEG_PYTHON', str(support_root() / 'tts-venv/bin/python'))


def model_root():
    return Path(os.environ.get('SOUNDPLOEG_MODEL_DIR', support_root() / 'models')).expanduser().resolve()


def voices():
    result = []
    for marker in sorted(model_root().glob('*/installed.json')):
        pack = json.loads(marker.read_text())
        for voice in pack['voices']:
            result.append(dict(voice, engine=pack['engine'], root=str(marker.parent)))
    return result


def resolve_voice(name, available):
    matches = [v for v in available if name.casefold() in (v['id'].casefold(), v['name'].casefold())]
    if len(matches) != 1:
        raise ValueError(f'Unknown or ambiguous voice {name!r}. Run soundploeg voices.')
    return matches[0]


def number(value, low, high, label):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or not low <= value <= high:
        raise ValueError(f'{label} must be a number between {low} and {high}')
    return float(value)


def chunks(text, limit=1200):
    """Split near sentence/word boundaries, preserving all non-whitespace text."""
    if not isinstance(text, str) or not text.strip():
        raise ValueError('Speech text must be a nonempty string')
    text = text.strip()
    while len(text) > limit:
        candidates = list(re.finditer(r'[.!?][\"\u201d\u2019\x27]?\s+|\n+', text[:limit]))
        cut = candidates[-1].end() if candidates else text.rfind(' ', 0, limit + 1)
        if cut < limit // 3:
            cut = limit
        yield text[:cut].strip()
        text = text[cut:].strip()
    if text:
        yield text


def prepare_episode(episode):
    if not isinstance(episode, dict) or not isinstance(episode.get('segments'), list) or not episode['segments']:
        raise ValueError('Episode must contain a nonempty segments array')
    speakers = episode.get('speakers', {})
    if not isinstance(speakers, dict):
        raise ValueError('speakers must map speaker names to voice names or IDs')
    available = voices()
    prepared = []
    for segment in episode['segments']:
        if not isinstance(segment, dict):
            raise ValueError('Each segment must be an object')
        voice_name = segment.get('voice') or speakers.get(segment.get('speaker'))
        if not isinstance(voice_name, str):
            raise ValueError('Each segment needs a voice or a speaker defined in speakers')
        voice = resolve_voice(voice_name, available)
        rate = number(segment.get('rate', 1.0), 0.5, 2.0, 'rate')
        pause = number(segment.get('pause_after', 0.35), 0, 10, 'pause_after')
        parts = list(chunks(segment.get('text')))
        for index, part in enumerate(parts):
            prepared.append(dict(voice=voice, text=part, rate=rate, pause=pause if index == len(parts) - 1 else 0.12))
    return prepared


class Worker:
    def __enter__(self):
        self.errors = tempfile.TemporaryFile(mode='w+t')
        try:
            self.process = subprocess.Popen([speech_python(), '-B', '-u', str(WORKER)],
                                            stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                            stderr=self.errors, text=True)
        except BaseException:
            self.errors.close()
            raise
        self.selector = selectors.DefaultSelector()
        self.selector.register(self.process.stdout, selectors.EVENT_READ)
        return self

    def synthesize(self, part, output):
        request = dict(id=str(uuid.uuid4()), root=part['voice']['root'], voice=part['voice']['id'],
                       text=part['text'], rate=part['rate'], output=str(output))
        self.process.stdin.write(json.dumps(request) + '\n')
        self.process.stdin.flush()
        if not self.selector.select(timeout=120):
            raise TimeoutError('Speech worker timed out after 120 seconds on one chunk')
        line = self.process.stdout.readline()
        if not line:
            self.errors.seek(0)
            raise RuntimeError('Speech worker exited: ' + self.errors.read()[-3000:])
        reply = json.loads(line)
        if reply.get('id') != request['id'] or not reply.get('ok'):
            raise RuntimeError(reply.get('error', 'Invalid speech worker reply'))

    def __exit__(self, *args):
        self.selector.close()
        self.process.stdin.close()
        try:
            self.process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait()
        self.process.stdout.close()
        self.errors.close()


def ffmpeg_path():
    return shutil.which('ffmpeg') or next((p for p in ('/opt/homebrew/bin/ffmpeg', '/usr/local/bin/ffmpeg') if os.access(p, os.X_OK)), None)


def render(episode, output, overwrite=False, progress=None):
    prepared = prepare_episode(episode)
    output = Path(output).expanduser().absolute()
    suffix = output.suffix.lower()
    if suffix not in ('.wav', '.mp3'):
        raise ValueError('Output must end in .wav or .mp3')
    if output.exists() and not overwrite:
        raise FileExistsError(f'Output already exists: {output}. Choose another name or use --overwrite.')
    ffmpeg = ffmpeg_path()
    mixed = len({p['voice']['engine'] for p in prepared}) > 1
    if (suffix == '.mp3' or mixed) and not ffmpeg:
        raise ValueError('MP3 and mixed-engine episodes require ffmpeg. Use WAV with one engine or install ffmpeg.')
    output.parent.mkdir(parents=True, exist_ok=True)
    # Same filesystem as destination allows an atomic final publish.
    with tempfile.TemporaryDirectory(prefix='.soundploeg-', dir=output.parent) as directory:
        directory = Path(directory)
        combined = directory / 'combined.wav'
        total_frames = 0
        with Worker() as worker, wave.open(str(combined), 'wb') as destination:
            # A valid empty header keeps cleanup from masking inference failures.
            destination.setparams((1, 2, 24000, 0, 'NONE', 'not compressed'))
            target_rate = 24000 if mixed else None
            for index, part in enumerate(prepared):
                chunk = directory / 'chunk.wav'
                worker.synthesize(part, chunk)
                if mixed:
                    converted = directory / 'resampled.wav'
                    subprocess.run([ffmpeg, '-v', 'error', '-y', '-i', str(chunk), '-ar', '24000', '-ac', '1', str(converted)], check=True, capture_output=True)
                    chunk = converted
                with wave.open(str(chunk), 'rb') as source:
                    if target_rate is None:
                        target_rate = source.getframerate()
                    if source.getnchannels() != 1 or source.getsampwidth() != 2 or source.getframerate() != target_rate:
                        raise ValueError('Unexpected speech audio format')
                    if index == 0:
                        destination.setparams((1, 2, target_rate, 0, 'NONE', 'not compressed'))
                    destination.writeframes(source.readframes(source.getnframes()))
                    total_frames += source.getnframes()
                pause_frames = round(part['pause'] * target_rate) if index < len(prepared) - 1 else 0
                destination.writeframes(b'\x00\x00' * pause_frames)
                total_frames += pause_frames
                if progress:
                    progress(index + 1, len(prepared))
            duration = total_frames / target_rate
        final = combined
        if suffix == '.mp3':
            final = directory / 'episode.mp3'
            subprocess.run([ffmpeg, '-v', 'error', '-y', '-i', str(combined), '-codec:a', 'libmp3lame', '-q:a', '2', str(final)], check=True, capture_output=True)
        if overwrite:
            os.replace(final, output)
        else:
            # Unlike replace(), link() cannot clobber a file created during rendering.
            os.link(final, output)
    return dict(output=str(output), duration=round(duration, 3), chunks=len(prepared), voices=sorted({p['voice']['id'] for p in prepared}))


def main():
    parser = argparse.ArgumentParser(description='Offline SoundPloeg speech and podcast rendering')
    sub = parser.add_subparsers(dest='command', required=True)
    sub.add_parser('voices', help='List installed voice names and IDs as JSON')
    sub.add_parser('doctor', help='Check runtime, models, and MP3 support')
    sub.add_parser('mcp', help='Run the local MCP server over stdio')
    speak = sub.add_parser('speak', help='Read a UTF-8 text file, stdin (-), or --text')
    speak.add_argument('input', nargs='?', help='Text file, or - for stdin')
    speak.add_argument('--text')
    speak.add_argument('--voice', default='Heart')
    speak.add_argument('--rate', type=float, default=1.0)
    podcast = sub.add_parser('podcast', help='Render an episode JSON file')
    podcast.add_argument('input')
    for command in (speak, podcast):
        command.add_argument('--output', required=True)
        command.add_argument('--overwrite', action='store_true')
    args = parser.parse_args()
    try:
        if args.command == 'voices':
            result = voices()
        elif args.command == 'doctor':
            import onnxruntime
            import kokoro_onnx
            import soundfile
            result = dict(python=sys.executable, models=str(model_root()), voices=voices(), ffmpeg=ffmpeg_path(), worker=str(WORKER))
            if not result['voices'] or not WORKER.exists():
                raise ValueError('Runtime or models missing. Run Scripts/bootstrap_tts.sh.')
        elif args.command == 'mcp':
            python = support_root() / 'mcp-venv/bin/python'
            if not python.exists():
                raise ValueError('MCP runtime missing. Run Scripts/install_agent_tools.py --mcp.')
            os.execv(str(python), [str(python), '-B', str(Path(__file__).with_name('soundploeg_mcp.py'))])
            return
        else:
            if args.command == 'speak':
                if (args.input is None) == (args.text is None):
                    parser.error('Provide either a text file/stdin or --text')
                text = args.text if args.text is not None else (sys.stdin.read() if args.input == '-' else Path(args.input).read_text())
                episode = {'segments': [dict(text=text, voice=args.voice, rate=args.rate, pause_after=0)]}
            else:
                episode = json.loads(Path(args.input).read_text())
            result = render(episode, args.output, args.overwrite,
                            lambda done, total: print(f'Rendered {done}/{total}', file=sys.stderr))
        print(json.dumps(result, indent=2))
    except (ValueError, OSError, RuntimeError, ImportError, wave.Error, subprocess.SubprocessError) as exc:
        print(f'SoundPloeg: {exc}', file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
