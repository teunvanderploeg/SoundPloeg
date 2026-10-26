import SwiftUI

/// Shared by the menu, shortcut reference, and application commands.
enum SpeechAction: String, CaseIterable, Identifiable {
    case speak, playQueue, pause, stop, skip, clear

    var id: Self { self }

    var title: String {
        switch self {
        case .speak: return "Read clipboard"
        case .playQueue: return "Play queue"
        case .pause: return "Pause / resume"
        case .stop: return "Stop"
        case .skip: return "Skip"
        case .clear: return "Clear queue"
        }
    }

    var key: KeyEquivalent {
        switch self {
        case .speak: return .return
        case .playQueue: return .return
        case .pause: return "p"
        case .stop: return "."
        case .skip: return .rightArrow
        case .clear: return .delete
        }
    }

    var modifiers: EventModifiers {
        switch self {
        case .speak, .stop: return .command
        case .playQueue, .pause, .skip, .clear: return [.command, .option]
        }
    }

    var shortcutLabel: String {
        switch self {
        case .speak: return "⌘↩"
        case .playQueue: return "⌥⌘↩"
        case .pause: return "⌥⌘P"
        case .stop: return "⌘."
        case .skip: return "⌥⌘→"
        case .clear: return "⌥⌘⌫"
        }
    }
}

struct SpeechActionButtons: View {
    @ObservedObject var appState: AppState

    var body: some View {
        ForEach(SpeechAction.allCases) { action in
            Button(action.title) {
                Task { await appState.perform(action) }
            }
            .keyboardShortcut(action.key, modifiers: action.modifiers)
            .disabled(!appState.canPerform(action))
        }
    }
}

@MainActor
struct SpeechCommands: Commands {
    @ObservedObject var appState: AppState
    var isPreview = false

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                SettingsWindowPresenter.shared.showSettings()
            }
            .keyboardShortcut(",", modifiers: .command)
            .disabled(isPreview)
        }
        CommandMenu("Speech") {
            SpeechActionButtons(appState: appState)
                .disabled(isPreview)
        }
    }
}

struct KeyboardShortcutReference: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            row(appState.autoSpeakOnHotkey ? "Speak clipboard from any app" : "Queue clipboard from any app",
                shortcut: appState.hotkeyShortcut.displayName)
            Divider()
            Text("When SoundPloeg is active")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(SpeechAction.allCases) { action in
                row(action.title, shortcut: action.shortcutLabel)
            }
            row("Settings", shortcut: "⌘,")
            row("Quit", shortcut: "⌘Q")
        }
    }

    private func row(_ title: String, shortcut: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(shortcut)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .accessibilityLabel("Shortcut: \(shortcut)")
        }
    }
}
