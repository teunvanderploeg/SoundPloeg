import Foundation

public enum ClipboardTextProcessor {
    public static let maxLength = 4_000
    public static let previewLength = 120

    public static func normalize(_ input: String) -> String {
        let replaced = input.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return replaced.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func validateAndBuildPayload(_ raw: String) throws -> ClipboardPayload {
        let normalized = normalize(raw)
        guard !normalized.isEmpty else {
            throw SoundPloegError.clipboardEmpty
        }

        if normalized.count > maxLength {
            let truncated = String(normalized.prefix(maxLength))
            return ClipboardPayload(
                normalizedText: truncated,
                preview: preview(for: truncated),
                warning: ErrorMapper.map(SoundPloegError.clipboardTooLong(max: maxLength, actual: normalized.count))
            )
        }

        return ClipboardPayload(normalizedText: normalized, preview: preview(for: normalized), warning: nil)
    }

    public static func preview(for text: String) -> String {
        guard text.count > previewLength else { return text }
        return String(text.prefix(previewLength)) + "..."
    }
}
