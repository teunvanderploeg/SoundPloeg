import XCTest
@testable import SoundPloegCore

final class HotkeyIngestionCoordinatorTests: XCTestCase {
    func testHotkeyAutoSpeakOffEnqueuesOnly() async throws {
        let diagnostics = TestDiagnosticsService()
        let tts = CountingTTSService()
        let playback = ImmediatePlayback()
        let queue = SpeechQueueCoordinator(ttsService: tts, playbackEngine: playback, diagnosticsService: diagnostics)

        let voice = VoiceDescriptor(id: "voice", name: "Voice", language: "en-US", modelPath: nil, configPath: nil, isSystem: false)
        await queue.setVoices([voice])

        let clipboard = StubClipboardService(text: "Hello from clipboard")
        let ingestion = HotkeyIngestionCoordinator(clipboardService: clipboard, queueCoordinator: queue) { _ in }

        _ = await ingestion.handleHotkey(selectedVoice: voice, rate: 1.0, autoSpeakOnHotkey: false)

        let depth = await queue.queueDepth()
        let calls = await tts.callCount()
        XCTAssertEqual(depth, 1)
        XCTAssertEqual(calls, 0)
    }

    func testHotkeyAutoSpeakOnStartsSynthesis() async throws {
        let diagnostics = TestDiagnosticsService()
        let tts = CountingTTSService()
        let playback = ImmediatePlayback()
        let queue = SpeechQueueCoordinator(ttsService: tts, playbackEngine: playback, diagnosticsService: diagnostics)

        let voice = VoiceDescriptor(id: "voice", name: "Voice", language: "en-US", modelPath: nil, configPath: nil, isSystem: false)
        await queue.setVoices([voice])

        let clipboard = StubClipboardService(text: "Hello from clipboard")
        let ingestion = HotkeyIngestionCoordinator(clipboardService: clipboard, queueCoordinator: queue) { _ in }

        _ = await ingestion.handleHotkey(selectedVoice: voice, rate: 1.0, autoSpeakOnHotkey: true)
        try await Task.sleep(nanoseconds: 80_000_000)

        let calls = await tts.callCount()
        XCTAssertGreaterThanOrEqual(calls, 1)
    }
}

private struct StubClipboardService: ClipboardService {
    let text: String

    func readNormalizedText() throws -> ClipboardPayload {
        try ClipboardTextProcessor.validateAndBuildPayload(text)
    }
}

private actor CountingTTSService: TTSService {
    private var count = 0

    func warmUp() async {}

    func availableVoices() async throws -> [VoiceDescriptor] {
        []
    }

    func synthesize(text: String, voice: VoiceDescriptor, rate: Float) async throws -> TTSOutput {
        count += 1
        return .audioFile(URL(fileURLWithPath: "/tmp/fake.wav"))
    }

    func callCount() async -> Int { count }
}

private actor ImmediatePlayback: AudioPlaybackEngine {
    func play(output: TTSOutput) async throws {}
    func pause() async {}
    func resume() async {}
    func stop() async {}
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
