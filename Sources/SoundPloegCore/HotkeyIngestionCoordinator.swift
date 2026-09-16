import Foundation

public final class HotkeyIngestionCoordinator {
    private let clipboardService: ClipboardService
    private let queueCoordinator: SpeechQueueCoordinator
    private let previewHandler: @Sendable (String) -> Void

    public init(
        clipboardService: ClipboardService,
        queueCoordinator: SpeechQueueCoordinator,
        previewHandler: @escaping @Sendable (String) -> Void
    ) {
        self.clipboardService = clipboardService
        self.queueCoordinator = queueCoordinator
        self.previewHandler = previewHandler
    }

    @discardableResult
    public func handleHotkey(
        selectedVoice: VoiceDescriptor,
        rate: Float,
        autoSpeakOnHotkey: Bool
    ) async -> UserMessage? {
        do {
            let payload = try clipboardService.readNormalizedText()
            previewHandler(payload.preview)

            let job = SpeechJob(text: payload.normalizedText, voiceID: selectedVoice.id, rate: rate)
            try await queueCoordinator.enqueue(job)

            if autoSpeakOnHotkey {
                await queueCoordinator.speakNowIfIdle()
            }

            return payload.warning
        } catch {
            return ErrorMapper.map(error)
        }
    }
}
