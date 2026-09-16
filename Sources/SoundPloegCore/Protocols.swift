import Foundation

public protocol SettingsStore: AnyObject {
    var selectedVoiceID: String? { get set }
    var speechRate: Float { get set }
    var autoSpeakOnHotkey: Bool { get set }
    var hotkeyShortcut: HotkeyShortcut { get set }
    var preferredModelRootPath: String? { get set }
    var speechHistoryData: Data? { get set }
}

public protocol ClipboardService {
    func readNormalizedText() throws -> ClipboardPayload
}

public protocol HotkeyService: AnyObject {
    func eventStream() -> AsyncStream<Void>
    func register(shortcut: HotkeyShortcut) throws
    func unregister()
}

public protocol TTSService {
    func cancelSynthesis() async
    func warmUp() async
    func availableVoices() async throws -> [VoiceDescriptor]
    func synthesize(text: String, voice: VoiceDescriptor, rate: Float) async throws -> TTSOutput
}

public protocol DiagnosticsService {
    func publish(_ message: UserMessage) async
    func clear() async
    func messages() async -> [UserMessage]
}

public protocol AudioPlaybackEngine {
    func play(output: TTSOutput) async throws
    func pause() async
    func resume() async
    func stop() async
}

public extension TTSService {
    func cancelSynthesis() async {}
}
