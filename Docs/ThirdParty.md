# Speech components

## Kokoro English

- Model: [Kokoro-82M v1.0 ONNX](https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX), FP32 export.
- Pinned revision: `1939ad2a8e416c0acfeecc08a694d14ef25f2231`.
- Model license: Apache-2.0, as declared in the model repository.
- Runtime: `kokoro-onnx==0.6.1`, with ONNX Runtime and the bundled espeak-ng phonemizer library.
- English voice vectors are downloaded separately, then combined into a local `voices.npz` cache.

## Supertonic Dutch

- Model: [Supertonic 3](https://huggingface.co/supertone-oss-archive/supertonic-3).
- Pinned revision: `aafc6e32416a594460b32413efc49d7fe4ce6d46`.
- Model license: OpenRAIL-M. The model's LICENSE is included in the downloaded pack.
- `Sources/SoundPloegInfra/Resources/Runtime/supertonic_inference.py` is the upstream `py/helper.py`, from [commit 1e9799e](https://github.com/supertone-oss-archive/supertonic/tree/1e9799e964ea4c0dad7cde993b65c3c813a7b373), included under MIT with `SUPERTONIC-LICENSE.txt`.
- The upstream repository was archived on September 9, 2026. We pin and bundle the helper so inference does not fetch code at runtime.
- The app uses five denoising steps and the F1/M1 preset styles.

## Runtime packages

Exact tested Python package versions are in `Scripts/tts-requirements.txt`.
Their license metadata and notices remain in the installed environment. These
include ONNX Runtime, NumPy, SoundFile/libsndfile, phonemizer, and espeak-ng.
The vendored helper and model weights have separate licenses; MIT for the
helper does not replace the model license.

Model downloading is the only runtime-related network operation. The worker
loads files from installed packs and communicates with Swift using stdin/stdout.
