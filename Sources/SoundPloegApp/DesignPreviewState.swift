import AppKit
import Foundation
import SwiftUI
import SoundPloegCore
import SoundPloegInfra

/// Deterministic UI data without reading preferences, registering hotkeys or starting speech workers.
@MainActor
enum DesignPreviewState {
    private static var window: NSWindow?

    static func show(_ state: AppState, menu: Bool) {
        if let window {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let content: AnyView
        if menu {
            content = AnyView(MenuBarContentView(appState: state).disabled(true).fixedSize(horizontal: false, vertical: true))
        } else {
            content = AnyView(SettingsWindowView(appState: state, isPreview: true).frame(minWidth: 880, minHeight: 640))
        }
        let host = NSHostingView(rootView: content)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: menu ? 320 : 960, height: menu ? 420 : 700),
                              styleMask: menu ? [.titled, .closable] : [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "SoundPloeg design preview"
        window.isReleasedWhenClosed = false
        window.contentView = host
        if menu {
            host.layoutSubtreeIfNeeded()
            window.setContentSize(NSSize(width: 320, height: host.fittingSize.height))
        } else {
            window.contentMinSize = NSSize(width: 880, height: 640)
        }
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
    static func make() -> AppState {
        let state = AppState(
            settings: PreviewSettings(),
            clipboard: PreviewClipboard(),
            appSupportURL: FileManager.default.temporaryDirectory.appendingPathComponent("SoundPloeg-DesignPreview"),
            startsAutomatically: false
        )
        let voices = [
            VoiceDescriptor(id: "preview-heart", name: "Heart", language: "en-US", modelPath: nil, configPath: nil, isSystem: false),
            VoiceDescriptor(id: "preview-michael", name: "Michael", language: "en-US", modelPath: nil, configPath: nil, isSystem: false),
            VoiceDescriptor(id: "preview-dutch", name: "Dutch Female", language: "nl-NL", modelPath: nil, configPath: nil, isSystem: false)
        ]
        state.availableVoices = voices
        state.activeVoice = voices.first
        Task {
            let library = ModelLibraryService(modelRootURL: FileManager.default.temporaryDirectory.appendingPathComponent("SoundPloeg-DesignPreview/models"))
            state.downloadableModels = (try? await library.catalog()) ?? []
            state.installedModelIDs = Set(state.downloadableModels.map(\.id))
        }
        state.speechHistory = [
            SpeechHistoryEntry(createdAt: Date(timeIntervalSince1970: 1_792_920_000),
                               text: "Read a selected article aloud, then return to it when you have time.",
                               voiceID: voices[0].id, voiceName: voices[0].name, rate: 1, audioFilePath: nil)
        ]
        return state
    }
}

private final class PreviewSettings: SettingsStore {
    var selectedVoiceID: String?
    var speechRate: Float = 1
    var autoSpeakOnHotkey = true
    var hotkeyShortcut = HotkeyShortcut(keyCode: 1, carbonModifiers: 0, displayName: "⌘⇧S")
    var preferredModelRootPath: String?
    var speechHistoryData: Data?
}

private struct PreviewClipboard: ClipboardService {
    func readNormalizedText() throws -> ClipboardPayload {
        throw SoundPloegError.unknown("Clipboard access is disabled in the design preview.")
    }
}
