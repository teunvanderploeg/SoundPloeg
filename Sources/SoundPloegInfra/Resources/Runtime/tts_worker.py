"""Offline JSON-lines speech worker. stdout is reserved for protocol replies."""
import contextlib
import json
import os
from pathlib import Path
import sys
import time
import traceback

os.environ.setdefault('OMP_NUM_THREADS', '4')
os.environ.setdefault('HF_HUB_OFFLINE', '1')

_engines = {}
_styles = {}


def load_engine(pack, root):
    cache_key = (pack['id'], str(root))
    if cache_key in _engines:
        return _engines[cache_key]
    import onnxruntime as ort
    opts = ort.SessionOptions()
    opts.intra_op_num_threads = min(4, os.cpu_count() or 2)
    opts.inter_op_num_threads = 1
    if pack['engine'] == 'kokoro':
        import numpy as np
        from kokoro_onnx import Kokoro
        # The upstream voice vectors share one engine. Cache a local npz for the API.
        voices = root / 'voices.npz'
        if not voices.exists():
            arrays = {v['key']: np.fromfile(root / 'voices' / (v['key'] + '.bin'), dtype=np.float32).reshape(-1, 1, 256) for v in pack['voices']}
            tmp = root / 'voices.tmp.npz'
            np.savez(tmp, **arrays)
            tmp.replace(voices)
        session = ort.InferenceSession(str(root / 'onnx/model.onnx'), sess_options=opts, providers=['CPUExecutionProvider'])
        engine = Kokoro.from_session(session, str(voices))
    elif pack['engine'] == 'supertonic':
        from supertonic_inference import TextToSpeech, load_cfgs, load_text_processor, load_onnx_all
        directory = str(root / 'onnx')
        engine = TextToSpeech(load_cfgs(directory), load_text_processor(directory), *load_onnx_all(directory, opts, ['CPUExecutionProvider']))
    else:
        raise ValueError('Unsupported speech engine')
    _engines[cache_key] = engine
    return engine


def handle(request):
    root = Path(request['root']).resolve()
    pack = json.loads((root / 'installed.json').read_text())
    voice = next(v for v in pack['voices'] if v['id'] == request['voice'])
    engine = load_engine(pack, root)
    if request.get('op') == 'warm':
        return {}
    text = request['text'].strip()
    if not text or len(text) > 2000:
        raise ValueError('Speech text must contain 1 to 2000 characters')
    speed = float(request.get('rate', 1.0))
    if not 0.5 <= speed <= 2.0:
        raise ValueError('Speech rate must be between 0.5 and 2.0')
    import numpy as np
    import soundfile as sf
    if pack['engine'] == 'kokoro':
        audio, sample_rate = engine.create(text, voice=voice['key'], speed=speed, lang='en-gb' if voice['language'] == 'en-GB' else 'en-us')
    else:
        from supertonic_inference import load_voice_style
        key = (str(root), voice['key'])
        if key not in _styles:
            _styles[key] = load_voice_style([str(root / 'voice_styles' / (voice['key'] + '.json'))])
        # Upstream's indexer uses uint16; unsupported supplementary characters are omitted.
        text = ''.join(c for c in text if ord(c) <= 0xffff)
        audio, duration = engine(text, 'nl', _styles[key], total_step=5, speed=speed)
        sample_rate = engine.sample_rate
        audio = audio[0, :int(float(duration[0]) * sample_rate)]
    audio = np.asarray(audio).reshape(-1)
    if audio.size == 0 or not np.isfinite(audio).all():
        raise ValueError('The speech engine returned invalid audio')
    output = Path(request['output'])
    temporary = output.with_suffix('.partial.wav')
    try:
        sf.write(temporary, audio, sample_rate, subtype='PCM_16')
        temporary.replace(output)
    finally:
        temporary.unlink(missing_ok=True)
    return {'output': str(output), 'duration': len(audio) / sample_rate, 'sampleRate': sample_rate}


def main():
    protocol = sys.stdout
    for line in sys.stdin:
        request = {}
        started = time.monotonic()
        try:
            request = json.loads(line)
            with contextlib.redirect_stdout(sys.stderr):
                result = handle(request)
            reply = dict(id=request['id'], ok=True, elapsed=time.monotonic() - started, **result)
        except Exception as exc:
            traceback.print_exc(file=sys.stderr)
            reply = {'id': request.get('id'), 'ok': False, 'error': str(exc)}
        protocol.write(json.dumps(reply) + '\n')
        protocol.flush()


if __name__ == '__main__':
    main()
