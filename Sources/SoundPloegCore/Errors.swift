import Foundation

public enum SoundPloegError: Error, LocalizedError, Equatable, Sendable {
    case clipboardUnavailable
    case clipboardEmpty
    case clipboardTooLong(max: Int, actual: Int)
    case queueFull(max: Int)
    case modelMissing(String)
    case modelConfigMissing(String)
    case pythonRuntimeMissing(String)
    case binaryMissing(String)
    case binaryNotExecutable(String)
    case synthesisFailed(String)
    case playbackFailed(String)
    case hotkeyRegistrationFailed(String)
    case invalidHotkey
    case unavailableVoice(String)
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .clipboardUnavailable:
            return "Clipboard is unavailable."
        case .clipboardEmpty:
            return "Clipboard does not contain valid text."
        case .clipboardTooLong(let max, let actual):
            return "Clipboard text is too long (\(actual) chars, max \(max))."
        case .queueFull(let max):
            return "Speech queue is full (max \(max))."
        case .modelMissing(let path):
            return "Model file missing at \(path)."
        case .modelConfigMissing(let path):
            return "Model config file missing at \(path)."
        case .pythonRuntimeMissing(let path):
            return "Speech runtime missing at \(path)."
        case .binaryMissing(let path):
            return "Speech binary missing at \(path)."
        case .binaryNotExecutable(let path):
            return "Speech binary is not executable at \(path)."
        case .synthesisFailed(let reason):
            return "Speech synthesis failed: \(reason)"
        case .playbackFailed(let reason):
            return "Playback failed: \(reason)"
        case .hotkeyRegistrationFailed(let reason):
            return "Hotkey registration failed: \(reason)"
        case .invalidHotkey:
            return "Selected hotkey is invalid."
        case .unavailableVoice(let voiceID):
            return "Voice \(voiceID) is unavailable."
        case .unknown(let reason):
            return "Unexpected error: \(reason)"
        }
    }
}

public enum ErrorMapper {
    public static func map(_ error: Error) -> UserMessage {
        guard let error = error as? SoundPloegError else {
            return UserMessage(
                title: "Unexpected Error",
                detail: error.localizedDescription,
                severity: .error
            )
        }

        switch error {
        case .clipboardUnavailable, .clipboardEmpty:
            return UserMessage(title: "Clipboard", detail: "Copy text first, then press the hotkey.", severity: .warning)
        case .clipboardTooLong(let max, _):
            return UserMessage(title: "Text Too Long", detail: "Input was truncated to \(max) characters.", severity: .warning)
        case .queueFull:
            return UserMessage(title: "Queue Full", detail: "Clear the queue or wait for current jobs to finish.", severity: .warning)
        case .modelMissing, .modelConfigMissing, .pythonRuntimeMissing, .binaryMissing, .binaryNotExecutable:
            return UserMessage(title: "Local Model Unavailable", detail: "Run bootstrap script or configure a valid model path.", severity: .warning)
        case .synthesisFailed(let reason):
            return UserMessage(title: "Synthesis Failed", detail: reason, severity: .warning)
        case .playbackFailed:
            return UserMessage(title: "Playback Failed", detail: "Audio output failed. Try stopping and speaking again.", severity: .error)
        case .hotkeyRegistrationFailed, .invalidHotkey:
            return UserMessage(title: "Hotkey", detail: "Could not register the selected shortcut.", severity: .error)
        case .unavailableVoice:
            return UserMessage(title: "Voice Unavailable", detail: "Pick another voice from settings.", severity: .warning)
        case .unknown(let reason):
            return UserMessage(title: "Unexpected Error", detail: reason, severity: .error)
        }
    }
}
