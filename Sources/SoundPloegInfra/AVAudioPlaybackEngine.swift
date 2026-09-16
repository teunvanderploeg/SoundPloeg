import AVFoundation
import Foundation
import SoundPloegCore

@MainActor
public final class AVAudioPlaybackEngine: NSObject, AudioPlaybackEngine, @preconcurrency AVSpeechSynthesizerDelegate {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let speechSynthesizer = AVSpeechSynthesizer()

    private var speechContinuation: CheckedContinuation<Void, Error>?
    private var audioContinuation: CheckedContinuation<Void, Error>?
    private var playbackID = UUID()
    private var activeUtterance: AVSpeechUtterance?

    public override init() {
        super.init()
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: nil)
        speechSynthesizer.delegate = self
    }

    public func play(output: TTSOutput) async throws {
        switch output {
        case .audioFile(let url):
            try await playAudioFile(url)
        case .systemSpeech(let request):
            try await speakSystem(request)
        }
    }

    public func pause() async {
        playerNode.pause()
        _ = speechSynthesizer.pauseSpeaking(at: .immediate)
    }

    public func resume() async {
        if audioContinuation != nil, engine.isRunning, !playerNode.isPlaying {
            playerNode.play()
        }
        _ = speechSynthesizer.continueSpeaking()
    }

    public func stop() async {
        playbackID = UUID()
        activeUtterance = nil
        playerNode.stop()
        speechSynthesizer.stopSpeaking(at: .immediate)
        audioContinuation?.resume(returning: ())
        audioContinuation = nil
        speechContinuation?.resume(returning: ())
        speechContinuation = nil
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard utterance === activeUtterance else { return }
        activeUtterance = nil
        speechContinuation?.resume(returning: ())
        speechContinuation = nil
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        guard utterance === activeUtterance else { return }
        activeUtterance = nil
        speechContinuation?.resume(returning: ())
        speechContinuation = nil
    }

    private func playAudioFile(_ url: URL) async throws {
        do {
            let file = try AVAudioFile(forReading: url)
            let id = UUID()
            playbackID = id
            playerNode.stop()
            engine.stop()
            engine.disconnectNodeOutput(playerNode)
            engine.connect(playerNode, to: engine.mainMixerNode, format: file.processingFormat)
            try engine.start()

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                self.audioContinuation = continuation
                self.playerNode.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self, self.playbackID == id else { return }
                        self.audioContinuation?.resume(returning: ())
                        self.audioContinuation = nil
                    }
                }
                self.playerNode.play()
            }
        } catch {
            throw SoundPloegError.playbackFailed(error.localizedDescription)
        }
    }

    private func speakSystem(_ request: SystemSpeechRequest) async throws {
        let utterance = AVSpeechUtterance(string: request.text)
        utterance.rate = max(AVSpeechUtteranceMinimumSpeechRate, min(AVSpeechUtteranceMaximumSpeechRate, request.rate * 0.5))

        if let id = request.voiceIdentifier, !id.isEmpty {
            utterance.voice = AVSpeechSynthesisVoice(identifier: id)
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.speechContinuation = continuation
            self.activeUtterance = utterance
            self.speechSynthesizer.speak(utterance)
        }
    }
}
