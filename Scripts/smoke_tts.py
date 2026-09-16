#!/usr/bin/env python3
"""Exercise every installed voice twice in one offline worker and validate WAV output."""
import argparse
import json
from pathlib import Path
import selectors
import subprocess
import sys
import tempfile
import time

import numpy as np
import soundfile as sf


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--worker', type=Path, default=Path(__file__).resolve().parents[1] / 'Sources/SoundPloegInfra/Resources/Runtime/tts_worker.py')
    args = parser.parse_args()
    records = []
    with tempfile.TemporaryDirectory(prefix='soundploeg-smoke-') as directory:
        output_root = args.output or Path(directory)
        output_root.mkdir(parents=True, exist_ok=True)
        process = subprocess.Popen([sys.executable, '-B', '-u', str(args.worker)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
        selector = selectors.DefaultSelector()
        selector.register(process.stdout, selectors.EVENT_READ)
        try:
            for marker in sorted(args.root.glob('*/installed.json')):
                pack = json.loads(marker.read_text())
                for voice in pack['voices']:
                    dutch = voice['language'].startswith('nl')
                    text = ('Goedemiddag! De trein naar Utrecht vertrekt over vijf minuten. Wilt u uw kaartje gereedhouden?' if dutch else 'Good afternoon! The train to London leaves in five minutes. Please have your ticket ready.')
                    for attempt in range(2):
                        target = output_root / f"{voice['id']}-{attempt}.wav"
                        request = dict(id=f"{voice['id']}-{attempt}", root=str(marker.parent.resolve()), voice=voice['id'], text=text, rate=1.0, output=str(target.resolve()))
                        start = time.monotonic()
                        process.stdin.write(json.dumps(request)+'\n')
                        process.stdin.flush()
                        if not selector.select(timeout=90):
                            raise TimeoutError('Speech worker did not reply within 90 seconds')
                        reply = json.loads(process.stdout.readline())
                        if not reply.get('ok'):
                            raise RuntimeError(reply)
                        audio, sample_rate = sf.read(target)
                        assert sample_rate in (24000, 44100)
                        assert np.isfinite(audio).all() and np.max(np.abs(audio)) > 0.01
                        duration = len(audio)/sample_rate
                        assert 1 < duration < 30, duration
                        elapsed = time.monotonic()-start
                        record = dict(voice=voice['id'], attempt=attempt, seconds=round(elapsed,3), audioSeconds=round(duration,3), realtimeFactor=round(elapsed/duration,3), sampleRate=sample_rate)
                        records.append(record)
                        print(json.dumps(record), flush=True)
            assert len(records) >= 12, 'Both voice packs must be installed'
            if args.output:
                (output_root/'benchmark.json').write_text(json.dumps(records,indent=2)+'\n')
        finally:
            selector.close()
            process.stdin.close()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()


if __name__ == '__main__':
    main()
