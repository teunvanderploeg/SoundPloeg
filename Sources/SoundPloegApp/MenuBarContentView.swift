import AppKit
import SoundPloegCore
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var appState: AppState
    @Environment(\.openWindow) private var openWindow

    private let maxClipboardPreviewCharacters = 90

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle()
                    .fill(colorForStatus(appState.status))
                    .frame(width: 10, height: 10)

                Text(statusLabel)
                    .font(.headline)
            }

            Text("Global shortcut: \(appState.hotkeyShortcut.displayName)")
                .font(.caption)
                .foregroundStyle(.secondary)
            SpeechActionButtons(appState: appState)

            if !appState.lastClipboardPreview.isEmpty,
               appState.lastClipboardPreview != "No clipboard text yet." {
                Text("Last transcript")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(clipboardPreview)
                    .font(.caption)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }

            Divider()

            Button("Settings…") {
                openSettingsWindow()
            }
            .keyboardShortcut(",", modifiers: .command)

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(12)
        .frame(width: 320)
    }

    private var statusLabel: String {
        switch appState.status {
        case .idle: return "Idle"
        case .speaking: return "Speaking"
        case .paused: return "Paused"
        case .error: return "Error"
        }
    }

    private var clipboardPreview: String {
        let trimmed = appState.lastClipboardPreview.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxClipboardPreviewCharacters else {
            return trimmed
        }

        let endIndex = trimmed.index(trimmed.startIndex, offsetBy: maxClipboardPreviewCharacters)
        return "\(trimmed[..<endIndex])..."
    }

    private func colorForStatus(_ status: AppStatus) -> Color {
        switch status {
        case .idle:
            return .gray
        case .speaking:
            return .green
        case .paused:
            return .orange
        case .error:
            return .yellow
        }
    }

    private func openSettingsWindow() {
        let menuWindow = NSApplication.shared.keyWindow

        NSApp.setActivationPolicy(.regular)
        openWindow(id: "settings")
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        NSApplication.shared.activate(ignoringOtherApps: true)

        menuWindow?.orderOut(nil)
    }
}
