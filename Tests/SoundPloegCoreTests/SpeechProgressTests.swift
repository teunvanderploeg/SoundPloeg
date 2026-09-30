import XCTest
@testable import SoundPloegCore

final class SpeechProgressTests: XCTestCase {
    private let voice = VoiceDescriptor(id: "voice", name: "Actual voice", language: "en-US", modelPath: nil, configPath: nil, isSystem: true)

    func testSnapshotTracksCurrentJobThroughPreparationPlaybackAndCompletion() async throws {
        let preparing = expectation(description: "preparing")
        let playing = expectation(description: "playing")
        let completed = expectation(description: "completed")
        let tts = HeldTTS(started: preparing)
        let playback = HeldPlayback(started: playing)
        let queue = SpeechQueueCoordinator(ttsService: tts, playbackEngine: playback,
                                          diagnosticsService: ProgressDiagnostics(),
                                          onJobCompletion: { _, _, _ in completed.fulfill() })
        await queue.setVoices([voice])
        let current = SpeechJob(text: "Current reading", voiceID: voice.id, rate: 1)
        try await queue.enqueue(current)
        try await queue.enqueue(SpeechJob(text: "Later clipboard", voiceID: voice.id, rate: 1))
        await queue.speakNowIfIdle()
        await fulfillment(of: [preparing], timeout: 2)
        var snapshot = await queue.snapshot()
        XCTAssertEqual(snapshot.currentSpeech?.job, current)
        XCTAssertEqual(snapshot.currentSpeech?.voiceName, voice.name)
        XCTAssertEqual(snapshot.currentSpeech?.phase, .preparing)
        XCTAssertEqual(snapshot.queueDepth, 1)
        await queue.clear()
        await tts.release()
        await fulfillment(of: [playing], timeout: 2)
        snapshot = await queue.snapshot()
        XCTAssertEqual(snapshot.currentSpeech?.phase, .playing)
        XCTAssertEqual(snapshot.currentSpeech?.chunkIndex, 1)
        XCTAssertEqual(snapshot.currentSpeech?.totalChunks, 1)
        await playback.finish()
        await fulfillment(of: [completed], timeout: 2)
        snapshot = await queue.snapshot()
        XCTAssertNil(snapshot.currentSpeech)
        XCTAssertEqual(snapshot.status, .idle)
    }

    func testPauseDuringPreparationHoldsAudioAndStopClearsCurrentReading() async throws {
        let preparing = expectation(description: "preparing")
        let mustNotPlay = expectation(description: "audio must not play while paused")
        mustNotPlay.isInverted = true
        let tts = HeldTTS(started: preparing)
        let playback = HeldPlayback(started: mustNotPlay)
        let queue = SpeechQueueCoordinator(ttsService: tts, playbackEngine: playback, diagnosticsService: ProgressDiagnostics())
        await queue.setVoices([voice])
        try await queue.enqueue(SpeechJob(text: "Reading", voiceID: voice.id, rate: 1))
        await queue.speakNowIfIdle()
        await fulfillment(of: [preparing], timeout: 2)
        await queue.pause()
        await tts.release()
        await fulfillment(of: [mustNotPlay], timeout: 0.15)
        var snapshot = await queue.snapshot()
        XCTAssertEqual(snapshot.status, .paused)
        XCTAssertNotNil(snapshot.currentSpeech)
        await queue.stop()
        snapshot = await queue.snapshot()
        XCTAssertEqual(snapshot.status, .idle)
        XCTAssertNil(snapshot.currentSpeech)
        XCTAssertEqual(snapshot.queueDepth, 0)
    }

    func testVeryLongUnicodeTextKeepsFinalSentenceAndWorkerSizedChunks() {
        let text = String(repeating: "Hello 👩🏽‍💻 wereld! ", count: 8_000) + "Final sentence."
        let chunks = SpeechQueueCoordinator.chunkedText(text, maxChunkLength: 280)
        XCTAssertTrue(chunks.allSatisfy { !$0.isEmpty && $0.count <= 280 })
        XCTAssertEqual(chunks.joined(separator: " "), text)
        XCTAssertTrue(chunks.last?.hasSuffix("Final sentence.") == true)
    }
}

private actor HeldTTS: TTSService {
    let started: XCTestExpectation
    var pending: CheckedContinuation<TTSOutput, Error>?
    var text = ""
    init(started: XCTestExpectation) { self.started = started }
    func warmUp() async {}
    func availableVoices() async throws -> [VoiceDescriptor] { [] }
    func synthesize(text: String, voice: VoiceDescriptor, rate: Float) async throws -> TTSOutput {
        self.text = text
        return try await withCheckedThrowingContinuation { continuation in
            pending = continuation
            started.fulfill()
        }
    }
    func release() {
        pending?.resume(returning: .systemSpeech(SystemSpeechRequest(text: text, voiceIdentifier: nil, rate: 1)))
        pending = nil
    }
    func cancelSynthesis() async {
        pending?.resume(throwing: CancellationError())
        pending = nil
    }
}

private actor HeldPlayback: AudioPlaybackEngine {
    let started: XCTestExpectation
    var pending: CheckedContinuation<Void, Never>?
    init(started: XCTestExpectation) { self.started = started }
    func play(output: TTSOutput) async throws {
        await withCheckedContinuation { continuation in
            pending = continuation
            started.fulfill()
        }
    }
    func finish() { pending?.resume(); pending = nil }
    func pause() async {}
    func resume() async {}
    func stop() async { finish() }
}

private actor ProgressDiagnostics: DiagnosticsService {
    func publish(_ message: UserMessage) async {}
    func clear() async {}
    func messages() async -> [UserMessage] { [] }
}
