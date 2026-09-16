import AppKit
import Foundation
import SoundPloegCore

public struct NSPasteboardClipboardService: ClipboardService {
    private let pasteboard: NSPasteboard

    public init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    public func readNormalizedText() throws -> ClipboardPayload {
        guard let value = pasteboard.string(forType: .string) else {
            throw SoundPloegError.clipboardUnavailable
        }
        return try ClipboardTextProcessor.validateAndBuildPayload(value)
    }
}
