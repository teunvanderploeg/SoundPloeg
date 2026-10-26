import AppKit
import PloegKit
import SoundPloegCore
import SwiftUI

@MainActor
struct MenuBarContentView: View {
    @ObservedObject var appState: AppState

    private let maxClipboardPreviewCharacters = 90

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 11) {
                PloegAppIcon(.sound, size: 38)
                VStack(alignment: .leading, spacing: 3) {
                    Text("SoundPloeg")
                        .font(.system(size: 17, weight: .semibold))
                    Text("Read text aloud")
                        .font(.system(size: 12))
                        .foregroundStyle(PloegTheme.muted)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                Circle().fill(colorForStatus(appState.status)).frame(width: 6, height: 6)
                Text(appState.statusLabel)
                    .font(.system(size: 12, weight: .medium))
                Spacer(minLength: 0)
                Text(appState.hotkeyShortcut.displayName)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(PloegTheme.muted)
            }

            SpeechMessageView(appState: appState)

            if !appState.availableVoices.isEmpty {
                VStack(spacing: 12) {
                    Picker("Voice", selection: Binding(
                        get: { appState.activeVoice?.id ?? "" },
                        set: { newID in
                            if let voice = appState.availableVoices.first(where: { $0.id == newID }) {
                                appState.setVoice(voice)
                            }
                        }
                    )) {
                        ForEach(appState.availableVoices, id: \.id) { voice in
                            Text("\(voice.name) · \(voice.language)").tag(voice.id)
                        }
                    }
                    .pickerStyle(.menu)
                    HStack {
                        Text("Speed")
                        Slider(value: Binding(
                            get: { Double(appState.speechRate) },
                            set: { appState.setRate(Float($0)) }
                        ), in: 0.6...1.6)
                        .labelsHidden()
                        .accessibilityLabel("Speaking speed")
                        Text(String(format: "%.1f×", appState.speechRate))
                            .monospacedDigit()
                            .frame(width: 34, alignment: .trailing)
                            .foregroundStyle(PloegTheme.muted)
                    }
                }
                .font(.system(size: 12))
                .padding(12)
                .background(PloegTheme.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(PloegTheme.line, lineWidth: 1))
            }

            if appState.currentSpeech != nil || appState.queueDepth > 0 {
                CurrentSpeechView(appState: appState)
            }
            SpeechPlaybackControls(appState: appState)

            if !appState.lastClipboardPreview.isEmpty,
               appState.lastClipboardPreview != "No clipboard text yet." {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Last clipboard")
                        .font(.system(size: 11, weight: .medium))
                    Text(clipboardPreview)
                        .font(.system(size: 12))
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
                .foregroundStyle(PloegTheme.muted)
            }

            Rectangle().fill(PloegTheme.line).frame(height: 1)
            HStack {
                Button {
                    openSettingsWindow()
                } label: {
                    Label("Settings", systemImage: "slider.horizontal.3")
                }
                .keyboardShortcut(",", modifiers: .command)
                .buttonStyle(.plain)
                .foregroundStyle(PloegTheme.accent)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q", modifiers: .command)
                    .buttonStyle(.plain)
                    .foregroundStyle(PloegTheme.muted)
            }
            .font(.system(size: 12))
        }
        .padding(18)
        .frame(width: 320)
        .foregroundStyle(PloegTheme.ink)
        .background(PloegTheme.canvas)
        .tint(PloegTheme.accent)
    }

    private var clipboardPreview: String {
        let trimmed = appState.lastClipboardPreview.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxClipboardPreviewCharacters else { return trimmed }
        let endIndex = trimmed.index(trimmed.startIndex, offsetBy: maxClipboardPreviewCharacters)
        return "\(trimmed[..<endIndex])..."
    }

    private func colorForStatus(_ status: AppStatus) -> Color {
        switch status {
        case .idle, .speaking: return PloegTheme.success
        case .paused: return PloegTheme.warning
        case .error: return PloegTheme.danger
        }
    }

    private func openSettingsWindow() {
        let menuWindow = NSApplication.shared.keyWindow
        let settingsWindow = SettingsWindowPresenter.shared.showSettings()
        if let menuWindow, menuWindow !== settingsWindow { menuWindow.orderOut(nil) }
    }
}
