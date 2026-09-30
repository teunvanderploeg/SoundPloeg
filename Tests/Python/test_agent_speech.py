import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import wave

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'Scripts'))
import soundploeg_cli as cli

VOICES = [dict(id='heart', name='Heart', engine='kokoro', root='/fake'),
          dict(id='michael', name='Michael', engine='kokoro', root='/fake')]


class FakeWorker:
    calls = []

    def __enter__(self):
        return self

    def __exit__(self, *args):
        pass

    def synthesize(self, part, output):
        self.calls.append(part)
        with wave.open(str(output), 'wb') as audio:
            audio.setparams((1, 2, 24000, 0, 'NONE', 'not compressed'))
            audio.writeframes(b'\x01\x00' * 2400)


class SpeechTests(unittest.TestCase):
    def test_chunks_preserve_long_text_and_obey_worker_limit(self):
        for text in ['A sentence. Another sentence! ' * 200, 'x' * 5000, 'woord ' * 700, 'Hallo.\n\n世界！ ' * 400]:
            parts = list(cli.chunks(text))
            self.assertGreater(len(parts), 1)
            self.assertTrue(all(0 < len(p) <= 1200 for p in parts))
            self.assertEqual(''.join(''.join(parts).split()), ''.join(text.split()))

    @patch.object(cli, 'voices', return_value=VOICES)
    def test_invalid_inputs_fail_before_rendering(self, _):
        for episode in [{}, {'segments': []}, {'segments': [{'voice': 'absent', 'text': 'hi'}]},
                        {'segments': [{'voice': 'Heart', 'text': ''}]},
                        {'segments': [{'voice': 'Heart', 'text': 'hi', 'rate': float('nan')}]},
                        {'segments': [{'voice': 'Heart', 'text': 'hi', 'pause_after': -1}]}]:
            with self.subTest(episode=episode), self.assertRaises(ValueError):
                cli.prepare_episode(episode)

    @patch.object(cli, 'voices', return_value=VOICES)
    @patch.object(cli, 'Worker', FakeWorker)
    def test_two_voices_pause_duration_and_no_overwrite(self, _):
        episode = {'speakers': {'a': 'heart', 'b': 'Michael'}, 'segments': [
            {'speaker': 'a', 'text': 'Hello.', 'pause_after': 0.5},
            {'speaker': 'b', 'text': 'Welcome.'}]}
        FakeWorker.calls = []
        with tempfile.TemporaryDirectory() as root:
            output = Path(root) / 'podcast.wav'
            result = cli.render(episode, output)
            self.assertEqual(result['duration'], 0.7)
            self.assertEqual([c['voice']['id'] for c in FakeWorker.calls], ['heart', 'michael'])
            with wave.open(str(output)) as audio:
                self.assertEqual(audio.getnframes(), 16800)
            original = output.read_bytes()
            with self.assertRaises(FileExistsError):
                cli.render(episode, output)
            self.assertEqual(output.read_bytes(), original)
            cli.render(episode, output, overwrite=True)
            self.assertEqual(list(Path(root).iterdir()), [output])

    @patch.object(cli, 'voices', return_value=VOICES)
    @patch.object(cli, 'Worker', FakeWorker)
    def test_failure_preserves_previous_output_and_cleans_temporary_audio(self, _):
        episode = {'segments': [{'voice': 'Heart', 'text': 'hi'}]}
        with tempfile.TemporaryDirectory() as root:
            output = Path(root) / 'out.wav'
            output.write_bytes(b'previous recording')
            with patch.object(FakeWorker, 'synthesize', side_effect=RuntimeError('inference failed')):
                with self.assertRaisesRegex(RuntimeError, 'inference failed'):
                    cli.render(episode, output, overwrite=True)
            self.assertEqual(output.read_bytes(), b'previous recording')
            self.assertEqual(list(Path(root).iterdir()), [output])

    @patch.object(cli, 'voices', return_value=VOICES)
    @patch.object(cli, 'ffmpeg_path', return_value=None)
    def test_missing_mp3_encoder_fails_before_worker(self, *_):
        with tempfile.TemporaryDirectory() as root, patch.object(cli, 'Worker') as worker:
            with self.assertRaisesRegex(ValueError, 'require ffmpeg'):
                cli.render({'segments': [{'voice': 'Heart', 'text': 'hi'}]}, Path(root) / 'out.mp3')
            worker.assert_not_called()


if __name__ == '__main__':
    unittest.main()
