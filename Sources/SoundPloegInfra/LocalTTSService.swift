import Foundation
import SoundPloegCore

public actor LocalTTSService: TTSService {
    private let modelRootURL: URL
    private let worker: SpeechWorker

    public init(pythonExecutableURL: URL, modelRootURL: URL) {
        self.modelRootURL = modelRootURL
        // Runtime is copied as a directory in both SwiftPM and Xcode builds.
        let script = VoiceCatalog.resourceBundle.resourceURL!
            .appendingPathComponent("Runtime/tts_worker.py")
        self.worker = SpeechWorker(python: pythonExecutableURL, script: script)
    }

    public func warmUp() async {
        // Models load on first use, then stay resident in the worker.
    }

    public func availableVoices() async throws -> [VoiceDescriptor] {
        try VoiceCatalog.scanInstalledVoices(modelRoot: modelRootURL)
    }

    public func cancelSynthesis() async { await worker.cancel() }

    public func synthesize(text: String, voice: VoiceDescriptor, rate: Float) async throws -> TTSOutput {
        guard !voice.isSystem, let root = voice.modelPath,
              try await availableVoices().contains(where: { $0.id == voice.id && $0.modelPath == root }) else {
            throw SoundPloegError.unavailableVoice(voice.id)
        }
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("soundploeg-\(UUID().uuidString).wav")
        do {
            try await worker.request([
                "op": "synthesize", "root": root, "voice": voice.id, "text": text,
                "rate": max(0.5, min(2.0, rate)), "output": output.path
            ])
            try Task.checkCancellation()
            guard FileManager.default.fileExists(atPath: output.path) else {
                throw SoundPloegError.synthesisFailed("Worker produced no audio file")
            }
            return .audioFile(output)
        } catch {
            try? FileManager.default.removeItem(at: output)
            try? FileManager.default.removeItem(at: output.deletingPathExtension().appendingPathExtension("partial.wav"))
            throw error
        }
    }
}
