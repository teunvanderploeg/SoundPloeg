import XCTest
@testable import SoundPloeg
import SoundPloegCore
import SoundPloegInfra

@MainActor
final class AppStateTests: XCTestCase {
    private let original = VoiceDescriptor(id: "original", name: "Original", language: "en-US", modelPath: nil, configPath: nil, isSystem: true)
    private let alternate = VoiceDescriptor(id: "alternate", name: "Alternate", language: "nl-NL", modelPath: nil, configPath: nil, isSystem: true)

    func testPlayQueueDoesNotReadOrDuplicateClipboard() async throws {
        let played = expectation(description: "queued item played")
        let tts = CapturingTTS()
        let queue = SpeechQueueCoordinator(ttsService: tts, playbackEngine: AppTestPlayback(played: played), diagnosticsService: InMemoryDiagnosticsService())
        await queue.setVoices([original])
        try await queue.enqueue(SpeechJob(text: "Previously queued", voiceID: original.id, rate: 1))
        let clipboard = ForbiddenClipboard()
        let app = AppState(settings: MemorySettings(), clipboard: clipboard, queue: queue, startsAutomatically: false)
        await app.playQueue()
        await fulfillment(of: [played], timeout: 2)
        let requests = await tts.requests
        XCTAssertEqual(requests.map(\.text), ["Previously queued"])
        XCTAssertEqual(clipboard.reads, 0)
    }

    func testReplayUsesOriginalVoiceAndRateWithoutClipboard() async throws {
        let played = expectation(description: "history replay played")
        let tts = CapturingTTS()
        let queue = SpeechQueueCoordinator(ttsService: tts, playbackEngine: AppTestPlayback(played: played), diagnosticsService: InMemoryDiagnosticsService())
        await queue.setVoices([original, alternate])
        let clipboard = ForbiddenClipboard()
        let app = AppState(settings: MemorySettings(), clipboard: clipboard, queue: queue, startsAutomatically: false)
        app.availableVoices = [original, alternate]
        app.activeVoice = alternate
        let entry = SpeechHistoryEntry(text: "Saved reading", voiceID: original.id, voiceName: original.name, rate: 0.8, audioFilePath: nil)
        await app.replayHistory(entry)
        await fulfillment(of: [played], timeout: 2)
        let request = await tts.requests.first
        XCTAssertEqual(request?.voiceID, original.id)
        XCTAssertEqual(request?.rate, 0.8)
        XCTAssertEqual(request?.text, entry.text)
        XCTAssertEqual(clipboard.reads, 0)
    }

    func testReplayWithCurrentVoiceWorksWhenOriginalIsMissing() async throws {
        let played = expectation(description: "alternate voice replay played")
        let tts = CapturingTTS()
        let queue = SpeechQueueCoordinator(ttsService: tts, playbackEngine: AppTestPlayback(played: played), diagnosticsService: InMemoryDiagnosticsService())
        await queue.setVoices([alternate])
        let app = AppState(settings: MemorySettings(), queue: queue, startsAutomatically: false)
        app.availableVoices = [alternate]
        app.activeVoice = alternate
        app.speechRate = 1.2
        let entry = SpeechHistoryEntry(text: "Saved reading", voiceID: original.id, voiceName: original.name, rate: 0.8, audioFilePath: nil)
        await app.replayHistory(entry)
        XCTAssertEqual(app.latestMessage?.title, "Voice Unavailable")
        let emptyDepth = await queue.queueDepth()
        XCTAssertEqual(emptyDepth, 0)
        await app.replayHistory(entry, useCurrentVoice: true)
        await fulfillment(of: [played], timeout: 2)
        let request = await tts.requests.first
        XCTAssertEqual(request?.voiceID, alternate.id)
        XCTAssertEqual(request?.rate, 1.2)
    }

    func testDeletingOneHistoryEntryPersistsOtherEntries() throws {
        let settings = MemorySettings()
        let removed = SpeechHistoryEntry(text: "Remove me", voiceID: original.id, voiceName: original.name, rate: 1, audioFilePath: nil)
        let kept = SpeechHistoryEntry(text: "Keep me", voiceID: alternate.id, voiceName: alternate.name, rate: 1, audioFilePath: nil)
        settings.speechHistoryData = try JSONEncoder().encode([removed, kept])
        let queue = SpeechQueueCoordinator(ttsService: CapturingTTS(), playbackEngine: AppTestPlayback(played: nil), diagnosticsService: InMemoryDiagnosticsService())
        let app = AppState(settings: settings, queue: queue, startsAutomatically: false)
        app.deleteHistoryEntry(removed)
        XCTAssertEqual(app.speechHistory, [kept])
        let saved = try JSONDecoder().decode([SpeechHistoryEntry].self, from: XCTUnwrap(settings.speechHistoryData))
        XCTAssertEqual(saved, [kept])
        XCTAssertEqual(app.latestMessage?.title, "History Item Deleted")
    }
}

private final class MemorySettings: SettingsStore {
    var selectedVoiceID: String?
    var speechRate: Float = 1
    var autoSpeakOnHotkey = true
    var hotkeyShortcut = HotkeyShortcut(keyCode: 1, carbonModifiers: 0, displayName: "Test")
    var preferredModelRootPath: String?
    var speechHistoryData: Data?
}

private final class ForbiddenClipboard: ClipboardService {
    var reads = 0
    func readNormalizedText() throws -> ClipboardPayload {
        reads += 1
        throw SoundPloegError.clipboardEmpty
    }
}

private actor CapturingTTS: TTSService {
    var requests: [SpeechJob] = []
    func warmUp() async {}
    func availableVoices() async throws -> [VoiceDescriptor] { [] }
    func synthesize(text: String, voice: VoiceDescriptor, rate: Float) async throws -> TTSOutput {
        requests.append(SpeechJob(text: text, voiceID: voice.id, rate: rate))
        return .systemSpeech(SystemSpeechRequest(text: text, voiceIdentifier: nil, rate: rate))
    }
}

private struct AppTestPlayback: AudioPlaybackEngine {
    let played: XCTestExpectation?
    func play(output: TTSOutput) async throws { played?.fulfill() }
    func pause() async {}
    func resume() async {}
    func stop() async {}
}
