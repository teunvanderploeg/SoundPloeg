import Foundation
import SoundPloegCore

public struct CompositeTTSService: TTSService {
    private let local: TTSService
    private let system: TTSService
    private let diagnostics: DiagnosticsService

    public init(local: TTSService, system: TTSService, diagnostics: DiagnosticsService) {
        self.local = local
        self.system = system
        self.diagnostics = diagnostics
    }

    public func cancelSynthesis() async {
        await local.cancelSynthesis()
        await system.cancelSynthesis()
    }

    public func warmUp() async {
        await local.warmUp()
        await system.warmUp()
    }

    public func availableVoices() async throws -> [VoiceDescriptor] {
        var all: [VoiceDescriptor] = []
        if let localVoices = try? await local.availableVoices() {
            all.append(contentsOf: localVoices)
        }
        let systemVoices = try await system.availableVoices()
        all.append(contentsOf: systemVoices)
        return all
    }

    public func synthesize(text: String, voice: VoiceDescriptor, rate: Float) async throws -> TTSOutput {
        if voice.isSystem {
            return try await system.synthesize(text: text, voice: voice, rate: rate)
        }

        do {
            return try await local.synthesize(text: text, voice: voice, rate: rate)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            await diagnostics.publish(
                UserMessage(
                    title: "Fallback Active",
                    detail: "Local model failed: \(error.localizedDescription) Using system voice for this request.",
                    severity: .warning
                )
            )

            let systemVoice = await bestSystemVoice(for: voice.language)
            return try await system.synthesize(text: text, voice: systemVoice, rate: rate)
        }
    }

    private func bestSystemVoice(for language: String) async -> VoiceDescriptor {
        guard let voices = try? await system.availableVoices() else {
            return VoiceDescriptor(id: "", name: "System Default", language: language, modelPath: nil, configPath: nil, isSystem: true)
        }
        if let exact = voices.first(where: { $0.language == language }) {
            return exact
        }
        let prefix = language.split(separator: "-").first.map(String.init) ?? language
        if let match = voices.first(where: { $0.language.hasPrefix(prefix) }) {
            return match
        }
        return voices.first ?? VoiceDescriptor(id: "", name: "System Default", language: language, modelPath: nil, configPath: nil, isSystem: true)
    }
}
