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

    func testValidatePreservesCompleteLongTextWithNotice() throws {
        let raw = String(repeating: "A long reading. ", count: 10_000) + "Final sentence."
        let payload = try ClipboardTextProcessor.validateAndBuildPayload(raw)

        XCTAssertEqual(payload.normalizedText, raw)
        XCTAssertEqual(payload.warning?.severity, .info)
        XCTAssertTrue(payload.preview.count < raw.count)
    }
}
