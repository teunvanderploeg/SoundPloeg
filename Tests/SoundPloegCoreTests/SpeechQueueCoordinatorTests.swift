import XCTest
@testable import SoundPloegCore

final class SpeechQueueCoordinatorTests: XCTestCase {
    func testQueueStateTransitions() async throws {
        let diagnostics = TestDiagnosticsService()
        let tts = TestTTSService()
        let playback = DelayedPlaybackEngine(delayNanos: 700_000_000)

        let queue = SpeechQueueCoordinator(
            ttsService: tts,
            playbackEngine: playback,
            diagnosticsService: diagnostics
        )

        let voice = VoiceDescriptor(id: "voice", name: "V", language: "en-US", modelPath: nil, configPath: nil, isSystem: false)
        await queue.setVoices([voice])
        try await queue.enqueue(SpeechJob(text: "Hello world", voiceID: voice.id, rate: 1.0))

        await queue.speakNowIfIdle()
        try await Task.sleep(nanoseconds: 80_000_000)
        let statusSpeaking = await queue.currentStatus()
        XCTAssertEqual(statusSpeaking, .speaking)

        await queue.pause()
        let statusPaused = await queue.currentStatus()
        XCTAssertEqual(statusPaused, .paused)

        await queue.resume()
        let statusResumed = await queue.currentStatus()
        XCTAssertEqual(statusResumed, .speaking)

        await queue.stop()
        let statusStopped = await queue.currentStatus()
        XCTAssertEqual(statusStopped, .idle)
    }

    func testSkipAndClearQueue() async throws {
        let diagnostics = TestDiagnosticsService()
        let tts = TestTTSService()
        let playback = DelayedPlaybackEngine(delayNanos: 800_000_000)

        let queue = SpeechQueueCoordinator(
            ttsService: tts,
            playbackEngine: playback,
            diagnosticsService: diagnostics
        )

        let voice = VoiceDescriptor(id: "voice", name: "V", language: "en-US", modelPath: nil, configPath: nil, isSystem: false)
        await queue.setVoices([voice])
        try await queue.enqueue(SpeechJob(text: "First", voiceID: voice.id, rate: 1.0))
        try await queue.enqueue(SpeechJob(text: "Second", voiceID: voice.id, rate: 1.0))

        await queue.speakNowIfIdle()
        try await Task.sleep(nanoseconds: 80_000_000)
        await queue.skip()
        await queue.clear()

        let depth = await queue.queueDepth()
        XCTAssertEqual(depth, 0)
    }
}

private actor TestDiagnosticsService: DiagnosticsService {
    private var items: [UserMessage] = []

    func publish(_ message: UserMessage) async {
        items.append(message)
    }

    func clear() async {
        items.removeAll()
    }

    func messages() async -> [UserMessage] {
        items
    }
}

private struct TestTTSService: TTSService {
    func warmUp() async {}

    func availableVoices() async throws -> [VoiceDescriptor] {
        []
    }

    func synthesize(text: String, voice: VoiceDescriptor, rate: Float) async throws -> TTSOutput {
        TTSOutput.audioFile(URL(fileURLWithPath: "/tmp/fake.wav"))
    }
}

private actor DelayedPlaybackEngine: AudioPlaybackEngine {
    private let delayNanos: UInt64

    init(delayNanos: UInt64) {
        self.delayNanos = delayNanos
    }

    func play(output: TTSOutput) async throws {
        try await Task.sleep(nanoseconds: delayNanos)
    }

    func pause() async {}
    func resume() async {}
    func stop() async {}
}

final class SpeechQueueInterruptionTests: XCTestCase {
    private let voice = VoiceDescriptor(id: "test", name: "Test", language: "nl-NL", modelPath: nil, configPath: nil, isSystem: false)

    func testChunkingPreservesPunctuationAndWords() {
        let text = "Hallo wereld! Hoe gaat het? Dit is een langere Nederlandse zin met woorden."
        let chunks = SpeechQueueCoordinator.chunkedText(text, maxChunkLength: 28)
        XCTAssertEqual(chunks.joined(separator: " "), text)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 28 })
        XCTAssertTrue(chunks.contains { $0.contains("!") })
        XCTAssertTrue(chunks.contains { $0.contains("?") })
    }

    func testStopDuringSynthesisDoesNotPlayLateAudio() async throws {
        let started = expectation(description: "synthesis started")
        let tts = BlockingFirstTTS(started: started)
        let playback = RecordingPlayback()
        let diagnostics = TestDiagnosticsService()
        let queue = SpeechQueueCoordinator(ttsService: tts, playbackEngine: playback, diagnosticsService: diagnostics)
        await queue.setVoices([voice])
        try await queue.enqueue(SpeechJob(text: "first", voiceID: voice.id, rate: 1))
        await queue.speakNowIfIdle()
        await fulfillment(of: [started], timeout: 2)
        await queue.stop()
        try await Task.sleep(nanoseconds: 50_000_000)
        let played = await playback.texts
        let messages = await diagnostics.messages()
        XCTAssertTrue(played.isEmpty)
        XCTAssertTrue(messages.isEmpty)
    }

    func testSkipDuringSynthesisContinuesWithNextJob() async throws {
        let started = expectation(description: "synthesis started")
        let played = expectation(description: "second job played")
        let tts = BlockingFirstTTS(started: started)
        let playback = RecordingPlayback(onPlay: played)
        let queue = SpeechQueueCoordinator(ttsService: tts, playbackEngine: playback, diagnosticsService: TestDiagnosticsService())
        await queue.setVoices([voice])
        for text in ["first", "second"] {
            try await queue.enqueue(SpeechJob(text: text, voiceID: voice.id, rate: 1))
        }
        await queue.speakNowIfIdle()
        await fulfillment(of: [started], timeout: 2)
        await queue.skip()
        await fulfillment(of: [played], timeout: 2)
        let texts = await playback.texts
        XCTAssertEqual(texts, ["second"])
        let overlapped = await tts.startedDuringCancellation
        XCTAssertFalse(overlapped)
    }
}

private actor BlockingFirstTTS: TTSService {
    let started: XCTestExpectation
    var continuation: CheckedContinuation<TTSOutput, Error>?
    var calls = 0
    var isCancelling = false
    var startedDuringCancellation = false
    init(started: XCTestExpectation) { self.started = started }
    func warmUp() async {}
    func availableVoices() async throws -> [VoiceDescriptor] { [] }
    func synthesize(text: String, voice: VoiceDescriptor, rate: Float) async throws -> TTSOutput {
        calls += 1
        if isCancelling { startedDuringCancellation = true }
        if calls == 1 {
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                started.fulfill()
            }
        }
        return .systemSpeech(SystemSpeechRequest(text: text, voiceIdentifier: nil, rate: rate))
    }
    func cancelSynthesis() async {
        isCancelling = true
        continuation?.resume(throwing: CancellationError())
        continuation = nil
        try? await Task.sleep(nanoseconds: 50_000_000)
        isCancelling = false
    }
}

private actor RecordingPlayback: AudioPlaybackEngine {
    var texts: [String] = []
    let onPlay: XCTestExpectation?
    init(onPlay: XCTestExpectation? = nil) { self.onPlay = onPlay }
    func play(output: TTSOutput) async throws {
        if case .systemSpeech(let request) = output { texts.append(request.text) }
        onPlay?.fulfill()
    }
    func pause() async {}
    func resume() async {}
    func stop() async {}
}
