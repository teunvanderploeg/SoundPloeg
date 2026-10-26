import AppKit
import PloegKit
import SwiftUI

/// A single settings window for every visible-open route.
@MainActor
final class SettingsWindowPresenter: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowPresenter()

    private var appState: AppState?
    private var launchOptions = AppLaunchOptions(arguments: [])
    private var settingsWindow: NSWindow?

    func configure(appState: AppState, launchOptions: AppLaunchOptions) {
        self.appState = appState
        self.launchOptions = launchOptions
    }

    func showInitialWindow() {
        if let destination = launchOptions.initialDestination { present(destination) }
    }

    func reopen() {
        present(launchOptions.reopenDestination)
    }

    @discardableResult
    func showSettings() -> NSWindow? {
        // Preview bundles must never expose a window with real action controls.
        if launchOptions.isDesignPreview {
            present(launchOptions.reopenDestination)
            return nil
        }
        guard let appState else { return nil }
        let window: NSWindow
        if let existing = settingsWindow {
            window = existing
        } else {
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 960, height: 700),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "SoundPloeg settings"
            window.identifier = NSUserInterfaceItemIdentifier("SoundPloeg.settings")
            window.isReleasedWhenClosed = false
            window.contentMinSize = NSSize(width: 880, height: 640)
            window.delegate = self
            window.contentView = NSHostingView(rootView:
                SettingsWindowView(appState: appState)
                    .frame(minWidth: 880, minHeight: 640)
                    .tint(PloegTheme.accent)
            )
            window.center()
            window.setFrameAutosaveName("SoundPloegSettings")
            settingsWindow = window
        }
        NSApp.setActivationPolicy(.regular)
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        NSApp.activate(ignoringOtherApps: true)
        return window
    }

    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === settingsWindow {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func present(_ destination: AppLaunchOptions.Destination) {
        switch destination {
        case .settings:
            showSettings()
        case .previewSettings:
            if let appState { DesignPreviewState.show(appState, menu: false) }
        case .previewMenu:
            if let appState { DesignPreviewState.show(appState, menu: true) }
        }
    }
}

@MainActor
final class SoundPloegApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        SettingsWindowPresenter.shared.showInitialWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindowPresenter.shared.reopen()
        return false
    }
}
