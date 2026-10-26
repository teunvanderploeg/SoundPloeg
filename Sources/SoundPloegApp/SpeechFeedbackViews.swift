import PloegKit
import SoundPloegCore
import SwiftUI

@MainActor
struct SpeechMessageView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        if let message = appState.latestMessage {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon(for: message.severity))
                    .foregroundStyle(color(for: message.severity))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(message.title).font(.system(size: 13, weight: .semibold))
                    Text(message.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(PloegTheme.muted)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 0)
                Button { appState.latestMessage = nil } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(PloegTheme.muted)
                .accessibilityLabel("Dismiss message")
                .help("Dismiss message")
            }
            .padding(12)
            .background(color(for: message.severity).opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(color(for: message.severity).opacity(0.2), lineWidth: 1))
        }
    }

    private func color(for severity: MessageSeverity) -> Color {
        switch severity {
        case .info: return PloegTheme.accent
        case .warning: return PloegTheme.warning
        case .error: return PloegTheme.danger
        }
    }

    private func icon(for severity: MessageSeverity) -> String {
        switch severity {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "exclamationmark.circle"
        }
    }
}

@MainActor
struct CurrentSpeechView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let speech = appState.currentSpeech {
                Text("Current reading")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(PloegTheme.muted)
                Text(ClipboardTextProcessor.preview(for: speech.job.text))
                    .font(.system(size: 13))
                    .lineLimit(3)
                Text("\(speech.voiceName) · Part \(speech.chunkIndex) of \(speech.totalChunks)")
                    .font(.system(size: 12))
                    .foregroundStyle(PloegTheme.muted)
                ProgressView(value: Double(speech.completedChunks), total: Double(max(1, speech.totalChunks)))
                    .tint(PloegTheme.accent)
                    .accessibilityLabel("Reading progress")
                    .accessibilityValue("\(speech.completedChunks) of \(speech.totalChunks) parts completed")
            }
            Text("\(appState.queueDepth) \(appState.queueDepth == 1 ? "item" : "items") waiting")
                .font(.system(size: 12))
                .foregroundStyle(PloegTheme.muted)
        }
    }
}

/// The same queue actions as the menu commands, grouped for a compact app surface.
@MainActor
struct SpeechPlaybackControls: View {
    @ObservedObject var appState: AppState
    var horizontal = false

    var body: some View {
        VStack(spacing: 8) {
            if horizontal {
                HStack(spacing: 10) { primaryActions }
            } else {
                VStack(spacing: 8) { primaryActions }
            }
            if appState.currentSpeech != nil || appState.queueDepth > 0 {
                HStack(spacing: 8) {
                    actionButton(.pause, label: appState.status == .paused ? "Resume" : "Pause", icon: appState.status == .paused ? "play.fill" : "pause.fill")
                    actionButton(.stop, label: "Stop", icon: "stop.fill")
                    actionButton(.skip, label: "Skip", icon: "forward.end.fill")
                }
                Button("Clear queue") { Task { await appState.perform(.clear) } }
                    .font(.system(size: 12))
                    .buttonStyle(.plain)
                    .foregroundStyle(PloegTheme.muted)
                    .keyboardShortcut(SpeechAction.clear.key, modifiers: SpeechAction.clear.modifiers)
                    .disabled(!appState.canPerform(.clear))
            }
        }
    }

    @ViewBuilder
    private var primaryActions: some View {
        Button { Task { await appState.perform(.speak) } } label: {
            Label("Read clipboard", systemImage: "play.fill").frame(maxWidth: .infinity)
        }
        .buttonStyle(PloegPrimaryButtonStyle())
        .keyboardShortcut(SpeechAction.speak.key, modifiers: SpeechAction.speak.modifiers)
        .disabled(!appState.canPerform(.speak))

        Button { Task { await appState.perform(.playQueue) } } label: {
            Label("Play queue", systemImage: "list.bullet").frame(maxWidth: .infinity)
        }
        .buttonStyle(PloegSecondaryButtonStyle())
        .keyboardShortcut(SpeechAction.playQueue.key, modifiers: SpeechAction.playQueue.modifiers)
        .disabled(!appState.canPerform(.playQueue))
    }

    private func actionButton(_ action: SpeechAction, label: String, icon: String) -> some View {
        Button { Task { await appState.perform(action) } } label: {
            Label(label, systemImage: icon).frame(maxWidth: .infinity)
        }
        .buttonStyle(PloegSecondaryButtonStyle())
        .keyboardShortcut(action.key, modifiers: action.modifiers)
        .disabled(!appState.canPerform(action))
    }
}
