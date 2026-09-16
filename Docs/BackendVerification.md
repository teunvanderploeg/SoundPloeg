# Backend verification, September 16, 2026

Test machine: Apple M1 Pro, macOS 26.6.2. CPU inference with four ONNX threads.

- Release preflight passed: Swift build, 21 Swift tests, Xcode project generation.
- The real-model integration test used the installed Application Support runtime and both actual model packs.
- Release Xcode build passed for arm64 and x86_64. Actual inference was tested on arm64 only.
- All six voices generated valid, non-silent WAV audio twice through the release app's bundled worker.
- App installed at `/Applications/SoundPloeg.app`; ad-hoc signature verified.
- The app exposed six local voices with no diagnostic errors during the UI check.
- The previous app is preserved at `.codex-tmp/SoundPloeg-before-backend-upgrade.app`.

## Measured generation

The warm pass below uses the same sentence per language, at normal speech rate.
Times exclude playback. They are short-passage checks, not a universal quality
or performance benchmark.

| Voice | Generation | Audio duration |
|---|---:|---:|
| Heart | 1.284 s | 5.056 s |
| Michael | 1.460 s | 5.717 s |
| Emma | 1.279 s | 4.779 s |
| George | 1.399 s | 5.632 s |
| Dutch Female | 1.152 s | 8.043 s |
| Dutch Male | 1.112 s | 8.052 s |

Across these warm samples, English generated at 3.9× real time and Dutch at
7.1× real time. The full model packs are 328 MB and 399 MB respectively,
excluding Python runtime dependencies. This upgrade favors local voice quality
and practical latency over minimum download size.

## Rejected English variants

The 92 MB INT8 export passed audio checks but needed around 4 seconds for a
5-second passage under the tested runtime. FP16 was faster, but Michael
returned non-finite audio. The chosen FP32 export passed all four voices and
was faster than INT8. No claim of subjective listening superiority is based
on these numerical checks.

## Coverage and limits

Tests cover worker reuse/restart, request timeout, cancellation without system
fallback, checksum rejection, resource packaging, stop/skip during synthesis,
and punctuation-preserving text splitting. The smoke script checks audio
structure, duration, sample rate, and finite nonzero samples. It does not grade
pronunciation or naturalness. Preview buttons in Settings allow direct voice
comparison.

Supertonic upstream is archived. The vendored helper, pinned model revisions,
and checksums make this installed version reproducible, but do not provide
future upstream maintenance. macOS system voice fallback remains available.
