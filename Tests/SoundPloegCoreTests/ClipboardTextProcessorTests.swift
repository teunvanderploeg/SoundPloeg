import XCTest
@testable import SoundPloegCore

final class ClipboardTextProcessorTests: XCTestCase {
    func testNormalizeCollapsesWhitespace() throws {
        let normalized = ClipboardTextProcessor.normalize("  hello\n\n world   from\tSoundPloeg ")
        XCTAssertEqual(normalized, "hello world from SoundPloeg")
    }

    func testValidateRejectsEmpty() {
        XCTAssertThrowsError(try ClipboardTextProcessor.validateAndBuildPayload(" \n\t ")) { error in
            XCTAssertEqual(error as? SoundPloegError, .clipboardEmpty)
        }
    }

    func testValidateTruncatesLongTextWithWarning() throws {
        let raw = String(repeating: "a", count: ClipboardTextProcessor.maxLength + 50)
        let payload = try ClipboardTextProcessor.validateAndBuildPayload(raw)

        XCTAssertEqual(payload.normalizedText.count, ClipboardTextProcessor.maxLength)
        XCTAssertNotNil(payload.warning)
    }
}
