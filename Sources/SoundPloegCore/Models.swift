import Foundation

public enum MessageSeverity: String, Codable, Sendable {
    case info
    case warning
    case error
}

public struct UserMessage: Equatable, Sendable {
    public let title: String
    public let detail: String
    public let severity: MessageSeverity

    public init(title: String, detail: String, severity: MessageSeverity) {
        self.title = title
        self.detail = detail
        self.severity = severity
    }
}

public enum AppStatus: Equatable, Sendable {
    case idle
    case speaking
    case paused
    case error(UserMessage)
}

public struct VoiceDescriptor: Hashable, Codable, Sendable {
    public let id: String
    public let name: String
    public let language: String
    public let modelPath: String?
    public let configPath: String?
    public let isSystem: Bool

    public init(
        id: String,
        name: String,
        language: String,
        modelPath: String?,
        configPath: String?,
        isSystem: Bool
    ) {
        self.id = id
        self.name = name
        self.language = language
        self.modelPath = modelPath
        self.configPath = configPath
        self.isSystem = isSystem
    }
}

public struct SpeechJob: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let text: String
    public let voiceID: String
    public let rate: Float
    public let sourceTimestamp: Date

    public init(
        id: UUID = UUID(),
        text: String,
        voiceID: String,
        rate: Float,
        sourceTimestamp: Date = Date()
    ) {
        self.id = id
        self.text = text
        self.voiceID = voiceID
        self.rate = rate
        self.sourceTimestamp = sourceTimestamp
    }
}

public enum SpeechPhase: Equatable, Sendable {
    case preparing
    case playing
}

public struct CurrentSpeech: Equatable, Sendable {
    public let job: SpeechJob
    public let voiceName: String
    public var phase: SpeechPhase
    public var chunkIndex: Int
    public let totalChunks: Int
    public var completedChunks: Int
}

public struct SpeechQueueSnapshot: Equatable, Sendable {
    public let status: AppStatus
    public let queueDepth: Int
    public let currentSpeech: CurrentSpeech?
}

public struct SystemSpeechRequest: Equatable, Sendable {
    public let text: String
    public let voiceIdentifier: String?
    public let rate: Float

    public init(text: String, voiceIdentifier: String?, rate: Float) {
        self.text = text
        self.voiceIdentifier = voiceIdentifier
        self.rate = rate
    }
}

public enum TTSOutput: Equatable, Sendable {
    case audioFile(URL)
    case systemSpeech(SystemSpeechRequest)
}

public struct HotkeyShortcut: Equatable, Codable, Sendable {
    public let keyCode: UInt32
    public let carbonModifiers: UInt32
    public let displayName: String

    public init(keyCode: UInt32, carbonModifiers: UInt32, displayName: String) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.displayName = displayName
    }
}

public struct ClipboardPayload: Equatable, Sendable {
    public let normalizedText: String
    public let preview: String
    public let warning: UserMessage?

    public init(normalizedText: String, preview: String, warning: UserMessage?) {
        self.normalizedText = normalizedText
        self.preview = preview
        self.warning = warning
    }
}

public struct ModelAsset: Hashable, Codable, Sendable {
    public let path: String
    public let url: String
    public let bytes: Int64
    public let sha256: String
}

public struct ModelVoice: Hashable, Codable, Sendable {
    public let id: String
    public let name: String
    public let language: String
    public let key: String
}

/// One downloadable engine pack can provide multiple voices without duplicating weights.
public struct DownloadableModel: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let name: String
    public let language: String
    public let quality: String
    public let sizeMB: Int
    public let engine: String
    public let repo: String
    public let revision: String
    public let files: [ModelAsset]
    public let voices: [ModelVoice]
}

public struct SpeechHistoryEntry: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let text: String
    public let voiceID: String
    public let voiceName: String
    public let rate: Float
    public var audioFilePath: String?

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        text: String,
        voiceID: String,
        voiceName: String,
        rate: Float,
        audioFilePath: String?
    ) {
        self.id = id
        self.createdAt = createdAt
        self.text = text
        self.voiceID = voiceID
        self.voiceName = voiceName
        self.rate = rate
        self.audioFilePath = audioFilePath
    }
}
