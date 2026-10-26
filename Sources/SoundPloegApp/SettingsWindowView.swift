import AppKit
import SoundPloegCore
import SwiftUI
import PloegKit

private enum SettingsTab: String, CaseIterable, Identifiable {
    case overview
    case playback
    case models
    case history
    case diagnostics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .playback: return "Playback"
        case .models: return "Models"
        case .history: return "History"
        case .diagnostics: return "Diagnostics"
        }
    }

    var subtitle: String {
        switch self {
        case .overview: return "Permissions and runtime"
        case .playback: return "Rate and hotkey"
        case .models: return "Installed and downloadable"
        case .history: return "Recent speech and audio files"
        case .diagnostics: return "Runtime messages"
        }
    }

    var icon: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .playback: return "waveform"
        case .models: return "externaldrive"
        case .history: return "clock.arrow.circlepath"
        case .diagnostics: return "stethoscope"
        }
    }
}

@MainActor
struct SettingsWindowView: View {
    @ObservedObject var appState: AppState
    var isPreview = false
    @State private var selectedTab: SettingsTab? = .overview
    @State private var historySearch = ""
    @State private var expandedHistoryIDs: Set<UUID> = []

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(PloegTheme.line).frame(width: 1)
            detail
        }
        .tint(PloegTheme.accent)
        .foregroundStyle(PloegTheme.ink)
        .background(PloegTheme.canvas)
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        .onDisappear {
            if !isPreview { NSApp.setActivationPolicy(.accessory) }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                PloegAppIcon(.sound, size: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text("SoundPloeg")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                    Text("Text to speech")
                        .font(.system(size: 12))
                        .foregroundStyle(PloegTheme.muted)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 26)
            .padding(.bottom, 28)

            VStack(spacing: 5) {
                ForEach(SettingsTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        HStack(spacing: 11) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 15, weight: .medium))
                                .frame(width: 20)
                            Text(tab.title)
                                .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .regular))
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(selectedTab == tab ? PloegTheme.accent : PloegTheme.muted)
                        .padding(.horizontal, 12)
                        .frame(height: 42)
                        .background(selectedTab == tab ? PloegTheme.accentSoft : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
                    .help(tab.subtitle)
                }
            }
            .padding(.horizontal, 12)
            Spacer(minLength: 24)
            VStack(alignment: .leading, spacing: 5) {
                Label("Runs on your Mac", systemImage: "desktopcomputer")
                    .font(.system(size: 12, weight: .medium))
                Text("English and Dutch voices")
                    .font(.system(size: 11))
            }
            .foregroundStyle(PloegTheme.muted)
            .padding(20)
        }
        .frame(width: 216)
        .background(PloegTheme.canvas)
    }

    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero
                SpeechMessageView(appState: appState)

                Group {
                    switch selectedTab ?? .overview {
                    case .overview:
                        overviewSection
                    case .playback:
                        playbackSection
                    case .models:
                        modelSection
                    case .history:
                        historySection
                    case .diagnostics:
                        diagnosticsSection
                    }
                }
                .disabled(isPreview)
            }
            .padding(28)
            .frame(maxWidth: 960, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(PloegTheme.canvas)
    }

    private var hero: some View {
        let tab = selectedTab ?? .overview
        return HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Text(tab.title)
                    .font(.system(size: 28, weight: .semibold))
                    .tracking(-0.6)
                Text(tab.subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(PloegTheme.muted)
            }
            Spacer(minLength: 12)
            PloegStatusPill(statusLabel, systemImage: statusIcon, color: statusColor)
        }
        .padding(.bottom, 8)
    }

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            card(title: "Playback", subtitle: "Current reading and waiting items") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("State: \(statusLabel)")
                    CurrentSpeechView(appState: appState)
                    Text("Last clipboard")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(appState.lastClipboardPreview)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }
            }

            card(title: "Keyboard shortcuts", subtitle: "Use the global shortcut from any app") {
                KeyboardShortcutReference(appState: appState)
            }

            card(title: "Quick actions", subtitle: "Control playback") {
                VStack(alignment: .leading, spacing: 8) {
                    SpeechPlaybackControls(appState: appState, horizontal: true)
                }
            }
        }
    }

    private var playbackSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            card(title: "Speed", subtitle: "Speech rate") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Rate: \(String(format: "%.2f", appState.speechRate))")
                        .foregroundStyle(.secondary)
                    Slider(value: Binding(
                        get: { Double(appState.speechRate) },
                        set: { appState.setRate(Float($0)) }
                    ), in: 0.6...1.6)
                }
            }

            card(title: "Hotkey", subtitle: "Global shortcut and behavior") {
                VStack(alignment: .leading, spacing: 10) {
                    HotkeyRecorderView(currentShortcut: appState.hotkeyShortcut) { shortcut in
                        Task { await appState.updateHotkey(shortcut) }
                    }
                    Toggle("Auto-speak on hotkey", isOn: Binding(
                        get: { appState.autoSpeakOnHotkey },
                        set: { appState.setAutoSpeak($0) }
                    ))
                }
            }
            card(title: "Keyboard shortcuts", subtitle: "Playback controls and app commands") {
                KeyboardShortcutReference(appState: appState)
            }
        }
    }

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            card(title: "Installed voices", subtitle: "English and Dutch voices, available offline") {
                if appState.localVoices.isEmpty {
                    Text("No local models installed")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Active voice", selection: Binding(
                            get: { appState.activeVoice?.id ?? "" },
                            set: { newID in
                                if let voice = appState.localVoices.first(where: { $0.id == newID }) {
                                    appState.setVoice(voice)
                                }
                            }
                        )) {
                            ForEach(appState.localVoices, id: \.id) { voice in
                                Text("\(voice.name) (\(voice.language))")
                                    .tag(voice.id)
                            }
                        }
                        .pickerStyle(.menu)

                        ForEach(appState.localVoices, id: \.id) { voice in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(voice.name)
                                    if let model = appState.downloadableModel(for: voice) {
                                        Text("\(voice.language) • \(model.name)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text(voice.language)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Button("Preview") {
                                    Task { await appState.previewVoice(voice) }
                                }
                                .buttonStyle(.bordered)

                                if appState.activeVoice?.id == voice.id {
                                    statusBadge("Active", isGood: true)
                                } else {
                                    Button("Use") {
                                        appState.setVoice(voice)
                                    }
                                    .buttonStyle(.bordered)
                                }

                                if let model = appState.downloadableModel(for: voice) {
                                    Button(appState.isModelRemoving(model) ? "Removing..." : "Remove pack") {
                                        Task { await appState.removeModel(model) }
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(appState.isModelRemoving(model))
                                }
                            }
                        }
                    }
                }
            }

            card(title: "Download", subtitle: "Download a voice pack once; voices share its model") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(appState.downloadableModels, id: \.id) { model in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(model.name) (\(model.language))")
                                Text("\(model.voices.count) voices • \(model.sizeMB) MB")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()

                            if appState.isModelInstalled(model) {
                                statusBadge("Installed", isGood: true)
                            } else {
                                Button(appState.isModelDownloading(model) ? "Downloading..." : "Download") {
                                    Task { await appState.downloadModel(model) }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(appState.isModelDownloading(model))
                            }
                        }
                    }
                }
            }
        }
    }

    private var diagnosticsSection: some View {
        card(title: "Diagnostics", subtitle: "Recent app warnings and errors") {
            if appState.diagnosticsMessages.isEmpty {
                Text("No issues")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(appState.diagnosticsMessages.suffix(30).enumerated()), id: \.offset) { _, msg in
                        Text("• \(msg.title): \(msg.detail)")
                            .foregroundStyle(msg.severity == .error ? .red : .secondary)
                    }
                }
            }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            card(title: "Saved audio", subtitle: "The latest three readings keep their WAV files") {
                if appState.recentHistoryWithAudio.isEmpty {
                    Text("No saved audio files yet")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(appState.recentHistoryWithAudio, id: \.id) { entry in
                            HStack(alignment: .top, spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.voiceName)
                                        .font(.subheadline.weight(.semibold))
                                    Text(entry.createdAt, style: .time)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(entry.text)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                Spacer()
                                Button("Download WAV") {
                                    appState.exportHistoryAudio(entry)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                    }
                }
            }

            card(title: "Reading history", subtitle: "Replay, copy, or inspect a previous reading") {
                TextField("Search text or voice", text: $historySearch)
                    .textFieldStyle(.roundedBorder)
                if appState.speechHistory.isEmpty {
                    Text("No speech history yet")
                        .foregroundStyle(.secondary)
                } else if filteredHistory.isEmpty {
                    Text("No readings match your search").foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(filteredHistory, id: \.id) { entry in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(entry.text)
                                    .lineLimit(expandedHistoryIDs.contains(entry.id) ? nil : 2)
                                    .textSelection(.enabled)
                                Text("\(entry.voiceName) • \(entry.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                HStack {
                                    Button("Replay") { Task { await appState.replayHistory(entry) } }
                                    Menu("More") {
                                        Button("Replay with current voice") {
                                            Task { await appState.replayHistory(entry, useCurrentVoice: true) }
                                        }
                                        .disabled(appState.activeVoice == nil)
                                        Button("Copy text") { appState.copyHistoryText(entry) }
                                        Button(expandedHistoryIDs.contains(entry.id) ? "Collapse text" : "Show full text") {
                                            if expandedHistoryIDs.contains(entry.id) {
                                                expandedHistoryIDs.remove(entry.id)
                                            } else {
                                                expandedHistoryIDs.insert(entry.id)
                                            }
                                        }
                                        if entry.audioFilePath != nil {
                                            Button("Export WAV…") { appState.exportHistoryAudio(entry) }
                                        }
                                        Divider()
                                        Button("Delete reading", role: .destructive) {
                                            appState.deleteHistoryEntry(entry)
                                            expandedHistoryIDs.remove(entry.id)
                                        }
                                    }
                                    Spacer()
                                    Text(entry.audioFilePath == nil ? "Text only" : "Audio kept")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 8)
                            Divider()
                        }

                        HStack {
                            Spacer()
                            Button("Clear history") {
                                appState.clearHistoryTextOnly()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
    }

    private var filteredHistory: [SpeechHistoryEntry] {
        let query = historySearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return appState.speechHistory }
        return appState.speechHistory.filter {
            $0.text.localizedCaseInsensitiveContains(query) || $0.voiceName.localizedCaseInsensitiveContains(query)
        }
    }

    private func card<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        PloegCard(title: title) {
            VStack(alignment: .leading, spacing: 12) {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(PloegTheme.muted)
                content()
                    .font(.system(size: 13))
            }
        }
    }

    private func statusBadge(_ title: String, isGood: Bool) -> some View {
        PloegStatusPill(title,
                        systemImage: isGood ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
                        color: isGood ? PloegTheme.success : PloegTheme.warning)
    }

    private var statusLabel: String {
        appState.statusLabel
    }

    private var statusColor: Color {
        switch appState.status {
        case .idle, .speaking: return PloegTheme.success
        case .paused: return PloegTheme.warning
        case .error: return PloegTheme.danger
        }
    }

    private var statusIcon: String {
        switch appState.status {
        case .idle: return "checkmark.circle.fill"
        case .speaking: return "waveform"
        case .paused: return "pause.circle.fill"
        case .error: return "exclamationmark.circle.fill"
        }
    }
}
