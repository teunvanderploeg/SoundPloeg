import SwiftUI

enum AppBrand {
    static let icon: NSImage = {
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
struct SoundPloegMenuBarApp: App {
    @StateObject private var appState = AppState()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.applicationIconImage = AppBrand.icon
    }

    var body: some Scene {
        MenuBarExtra(
            isPreparingSpeech ? "SoundPloeg: Preparing speech" : "SoundPloeg",
            systemImage: isPreparingSpeech ? "hourglass" : "waveform"
        ) {
            MenuBarContentView(appState: appState)
        }
        .menuBarExtraStyle(.window)

        Window("Settings", id: "settings") {
            SettingsWindowView(appState: appState)
                .frame(minWidth: 1180, minHeight: 760)
        }
        .windowResizability(.contentSize)
        .commands { SpeechCommands(appState: appState) }
    }

    private var isPreparingSpeech: Bool {
        appState.status == .speaking && appState.currentSpeech?.phase == .preparing
    }
}
