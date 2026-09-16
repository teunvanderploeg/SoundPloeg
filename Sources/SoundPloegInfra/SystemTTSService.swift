import AVFoundation
import Foundation
import SoundPloegCore

public struct SystemTTSService: TTSService {
    public init() {}

    public func warmUp() async {}

    public func availableVoices() async throws -> [VoiceDescriptor] {
        AVSpeechSynthesisVoice.speechVoices().map {
            VoiceDescriptor(
                id: $0.identifier,
                name: $0.name,
                language: $0.language,
                modelPath: nil,
                configPath: nil,
                isSystem: true
            )
        }
    }

    public func synthesize(text: String, voice: VoiceDescriptor, rate: Float) async throws -> TTSOutput {
        TTSOutput.systemSpeech(SystemSpeechRequest(text: text, voiceIdentifier: voice.id, rate: rate))
    }
}
