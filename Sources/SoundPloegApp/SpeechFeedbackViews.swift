import SoundPloegCore
import SwiftUI

struct SpeechMessageView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        if let message = appState.latestMessage {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon(for: message.severity))
                    .foregroundStyle(message.severity == .error ? Color.red : Color.primary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(message.title).font(.callout.weight(.semibold))
                    Text(message.detail).font(.caption).textSelection(.enabled)
                }
                Spacer(minLength: 0)
                Button {
                    appState.latestMessage = nil
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss message")
                .help("Dismiss message")
            }
            .padding(10)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
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

struct CurrentSpeechView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let speech = appState.currentSpeech {
                Text("Current reading").font(.caption).foregroundStyle(.secondary)
                Text(ClipboardTextProcessor.preview(for: speech.job.text))
                    .font(.callout)
                    .lineLimit(3)
                Text("\(speech.voiceName) · Part \(speech.chunkIndex) of \(speech.totalChunks)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ProgressView(value: Double(speech.completedChunks), total: Double(max(1, speech.totalChunks)))
                    .accessibilityLabel("Reading progress")
                    .accessibilityValue("\(speech.completedChunks) of \(speech.totalChunks) parts completed")
            }
            Text("\(appState.queueDepth) \(appState.queueDepth == 1 ? "item" : "items") waiting")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
