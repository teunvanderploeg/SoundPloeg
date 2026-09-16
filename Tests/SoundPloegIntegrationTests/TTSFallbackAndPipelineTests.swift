import XCTest
import SoundPloegCore
import SoundPloegInfra

final class TTSFallbackAndPipelineTests: XCTestCase {
    func testCompositeFallsBackToSystemOnLocalFailure() async throws {
        let diagnostics = InMemoryDiagnosticsService()
        let local = FailingLocalTTS()
        let system = StubSystemTTS()
        let composite = CompositeTTSService(local: local, system: system, diagnostics: diagnostics)

        let voice = VoiceDescriptor(
            id: "local-en",
            name: "Local EN",
            language: "en-US",
            modelPath: "/tmp/missing.onnx",
            configPath: "/tmp/missing.json",
            isSystem: false
        )

        let output = try await composite.synthesize(text: "hello", voice: voice, rate: 1.0)

        switch output {
        case .systemSpeech:
            break
        default:
            XCTFail("Expected system fallback output")
        }

        let items = await diagnostics.messages()
        XCTAssertTrue(items.contains { $0.title == "Fallback Active" })
    }

    func testIntegrationClipboardToHotkeyToQueuedSynthesis() async throws {
        let diagnostics = InMemoryDiagnosticsService()
        let tts = CountingTTS()
        let playback = NoopPlayback()
        let queue = SpeechQueueCoordinator(ttsService: tts, playbackEngine: playback, diagnosticsService: diagnostics)

        let voice = VoiceDescriptor(id: "local-en", name: "Local EN", language: "en-US", modelPath: nil, configPath: nil, isSystem: false)
        await queue.setVoices([voice])

        let clipboard = StubClipboard("integration hello")
        let hotkey = MockHotkeyService()

        let ingestion = HotkeyIngestionCoordinator(clipboardService: clipboard, queueCoordinator: queue) { _ in }

        let listener = Task {
            for await _ in hotkey.eventStream() {
                _ = await ingestion.handleHotkey(selectedVoice: voice, rate: 1.0, autoSpeakOnHotkey: true)
            }
        }

        hotkey.emit()
        try await Task.sleep(nanoseconds: 120_000_000)

        let synthCalls = await tts.count()
        XCTAssertGreaterThanOrEqual(synthCalls, 1)
        listener.cancel()
    }
}

private struct FailingLocalTTS: TTSService {
    func warmUp() async {}
    func availableVoices() async throws -> [VoiceDescriptor] { [] }
    func synthesize(text: String, voice: VoiceDescriptor, rate: Float) async throws -> TTSOutput {
        throw SoundPloegError.synthesisFailed("boom")
    }
}

private struct StubSystemTTS: TTSService {
    func warmUp() async {}
    func availableVoices() async throws -> [VoiceDescriptor] {
        [VoiceDescriptor(id: "sys-en", name: "System", language: "en-US", modelPath: nil, configPath: nil, isSystem: true)]
    }
    func synthesize(text: String, voice: VoiceDescriptor, rate: Float) async throws -> TTSOutput {
        .systemSpeech(SystemSpeechRequest(text: text, voiceIdentifier: voice.id, rate: rate))
    }
}

private actor CountingTTS: TTSService {
    private var calls = 0

    func warmUp() async {}
    func availableVoices() async throws -> [VoiceDescriptor] { [] }
    func synthesize(text: String, voice: VoiceDescriptor, rate: Float) async throws -> TTSOutput {
        calls += 1
        return .audioFile(URL(fileURLWithPath: "/tmp/fake.wav"))
    }

    func count() async -> Int { calls }
}

private actor NoopPlayback: AudioPlaybackEngine {
    func play(output: TTSOutput) async throws {}
    func pause() async {}
    func resume() async {}
    func stop() async {}
}

private struct StubClipboard: ClipboardService {
    let value: String
    init(_ value: String) { self.value = value }

    func readNormalizedText() throws -> ClipboardPayload {
        try ClipboardTextProcessor.validateAndBuildPayload(value)
    }
}

private final class MockHotkeyService: HotkeyService {
    private var continuation: AsyncStream<Void>.Continuation?
    private var pendingEvents = 0
    private lazy var stream: AsyncStream<Void> = {
        AsyncStream { continuation in
            self.continuation = continuation
            if self.pendingEvents > 0 {
                for _ in 0..<self.pendingEvents {
                    continuation.yield(())
                }
                self.pendingEvents = 0
            }
        }
    }()

    func eventStream() -> AsyncStream<Void> { stream }
    func register(shortcut: HotkeyShortcut) throws {}
    func unregister() {}

    func emit() {
        if let continuation {
            continuation.yield(())
        } else {
            pendingEvents += 1
        }
    }
}

private struct CancelledLocalTTS: TTSService {
    func warmUp() async {}
    func availableVoices() async throws -> [VoiceDescriptor] { [] }
    func synthesize(text: String, voice: VoiceDescriptor, rate: Float) async throws -> TTSOutput {
        throw CancellationError()
    }
}

extension TTSFallbackAndPipelineTests {
    func testCancellationNeverFallsBackToSystemSpeech() async throws {
        let diagnostics = InMemoryDiagnosticsService()
        let composite = CompositeTTSService(local: CancelledLocalTTS(), system: StubSystemTTS(), diagnostics: diagnostics)
        let voice = VoiceDescriptor(id: "local", name: "Local", language: "nl-NL", modelPath: nil, configPath: nil, isSystem: false)
        do {
            _ = try await composite.synthesize(text: "stop", voice: voice, rate: 1)
            XCTFail("Cancellation should propagate")
        } catch { XCTAssertTrue(error is CancellationError) }
        let messages = await diagnostics.messages()
        XCTAssertTrue(messages.isEmpty)
    }
}
