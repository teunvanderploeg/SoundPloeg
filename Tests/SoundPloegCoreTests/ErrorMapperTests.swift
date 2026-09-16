import XCTest
@testable import SoundPloegCore

final class ErrorMapperTests: XCTestCase {
    func testMapsModelMissingToWarning() {
        let message = ErrorMapper.map(SoundPloegError.modelMissing("/missing/model.onnx"))
        XCTAssertEqual(message.severity, .warning)
        XCTAssertEqual(message.title, "Local Model Unavailable")
    }

    func testMapsPlaybackToError() {
        let message = ErrorMapper.map(SoundPloegError.playbackFailed("device busy"))
        XCTAssertEqual(message.severity, .error)
        XCTAssertEqual(message.title, "Playback Failed")
    }
}
