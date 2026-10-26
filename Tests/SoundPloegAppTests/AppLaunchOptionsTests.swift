import XCTest
@testable import SoundPloeg

final class AppLaunchOptionsTests: XCTestCase {
    func testOrdinaryLaunchKeepsMenuBarBehaviorButReopenShowsSettings() {
        let options = AppLaunchOptions(arguments: ["SoundPloeg"])
        XCTAssertNil(options.initialDestination)
        XCTAssertEqual(options.reopenDestination, .settings)
        XCTAssertFalse(options.isDesignPreview)
    }

    func testToolboxColdLaunchOpensSettings() {
        let options = AppLaunchOptions(arguments: ["SoundPloeg", "--show-settings"])
        XCTAssertEqual(options.initialDestination, .settings)
        XCTAssertEqual(options.reopenDestination, .settings)
        XCTAssertFalse(options.isDesignPreview)
    }

    func testExternalOpenCannotEscapeBundlePreviewIsolation() {
        let options = AppLaunchOptions(arguments: ["SoundPloeg", "--show-settings"],
                                       info: ["PloegDesignPreview": true])
        XCTAssertTrue(options.isDesignPreview)
        XCTAssertEqual(options.initialDestination, .previewSettings)
        XCTAssertEqual(options.reopenDestination, .previewSettings)
    }

    func testMenuPreviewRemainsMenuPreviewOnColdAndWarmOpen() {
        let options = AppLaunchOptions(arguments: ["SoundPloeg", "--show-settings"],
                                       info: ["PloegDesignPreview": true, "PloegDesignPreviewMode": "menu"])
        XCTAssertEqual(options.initialDestination, .previewMenu)
        XCTAssertEqual(options.reopenDestination, .previewMenu)
    }

    func testModeMetadataAloneDoesNotEnablePreview() {
        let options = AppLaunchOptions(arguments: ["SoundPloeg", "--show-settings"],
                                       info: ["PloegDesignPreviewMode": "menu"])
        XCTAssertFalse(options.isDesignPreview)
        XCTAssertEqual(options.initialDestination, .settings)
    }

    func testCommandLinePreviewTakesPriorityOverShowSettings() {
        let settings = AppLaunchOptions(arguments: ["SoundPloeg", "--show-settings", "--design-preview"])
        let menu = AppLaunchOptions(arguments: ["SoundPloeg", "--show-settings", "--design-preview-menu"])
        XCTAssertEqual(settings.initialDestination, .previewSettings)
        XCTAssertEqual(settings.reopenDestination, .previewSettings)
        XCTAssertEqual(menu.initialDestination, .previewMenu)
        XCTAssertEqual(menu.reopenDestination, .previewMenu)
    }
}
