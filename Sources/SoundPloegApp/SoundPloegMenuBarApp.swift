import PloegKit
import SwiftUI

@MainActor
enum AppBrand {
    static let icon: NSImage = {
        if let image = PloegAssets.image(for: .sound) { return image }
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: "AppIcon", withExtension: "icns"),
              let image = NSImage(contentsOf: url) else {
            return NSImage(named: NSImage.applicationIconName) ?? NSImage()
        }
        return image
    }()
}

@main
@MainActor
struct SoundPloegMenuBarApp: App {
    @StateObject private var appState: AppState
    @NSApplicationDelegateAdaptor(SoundPloegApplicationDelegate.self) private var applicationDelegate

    private static var launchOptions: AppLaunchOptions {
        AppLaunchOptions(arguments: ProcessInfo.processInfo.arguments, info: Bundle.main.infoDictionary ?? [:])
    }

    init() {
        let options = Self.launchOptions
        let state = options.isDesignPreview ? DesignPreviewState.make() : AppState()
        _appState = StateObject(wrappedValue: state)
        NSApplication.shared.setActivationPolicy(options.isDesignPreview ? .regular : .accessory)
        NSApplication.shared.applicationIconImage = AppBrand.icon
        SettingsWindowPresenter.shared.configure(appState: state, launchOptions: options)
    }

    var body: some Scene {
        MenuBarExtra(
            isPreparingSpeech ? "SoundPloeg: Preparing speech" : "SoundPloeg",
            systemImage: isPreparingSpeech ? "hourglass" : "waveform",
            isInserted: .constant(!Self.launchOptions.isDesignPreview)
        ) {
            MenuBarContentView(appState: appState)
        }
        .menuBarExtraStyle(.window)

        .commands { SpeechCommands(appState: appState, isPreview: Self.launchOptions.isDesignPreview) }
    }

    private var isPreparingSpeech: Bool {
        appState.status == .speaking && appState.currentSpeech?.phase == .preparing
    }
}
