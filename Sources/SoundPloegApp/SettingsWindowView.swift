import AppKit
import SoundPloegCore
import SwiftUI

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

struct SettingsWindowView: View {
    @ObservedObject var appState: AppState
    @State private var selectedTab: SettingsTab? = .overview

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .preferredColorScheme(.dark)
        .background(background)
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        .onDisappear {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private var sidebar: some View {
        ZStack {
            background

            List(SettingsTab.allCases, selection: $selectedTab) { tab in
                HStack(spacing: 10) {
                    Image(systemName: tab.icon)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(selectedTab == tab ? .white : .primary)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(tab.title)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                        Text(tab.subtitle)
                            .font(.caption2)
                            .foregroundStyle(selectedTab == tab ? .white.opacity(0.85) : .secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 6)
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(selectedTab == tab ? Color.blue.opacity(0.9) : Color.clear)
                        .padding(.vertical, 2)
                )
                .foregroundStyle(selectedTab == tab ? .white : .primary)
                .tag(tab)
            }
            .scrollContentBackground(.hidden)
            .listStyle(.sidebar)
            .safeAreaInset(edge: .top) {
                HStack(spacing: 10) {
                    Image(nsImage: AppBrand.icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("SoundPloeg")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                        Text("Settings")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 6)
                .background(.ultraThinMaterial.opacity(0.25))
            }
        }
        .frame(minWidth: 290)
    }

    private var detail: some View {
        ZStack {
            background

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    hero

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
                .padding(20)
            }
        }
    }

    private var hero: some View {
        let tab = selectedTab ?? .overview

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Image(systemName: tab.icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(tab.title)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text(tab.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                HStack(spacing: 8) {
                    statusBadge(statusLabel, isGood: !isErrorStatus)
                    statusBadge("Voices \(appState.localVoices.count)", isGood: !appState.localVoices.isEmpty)
                }
            }

            HStack(spacing: 14) {
                labeledRuntime("Queue", value: "\(appState.queueDepth)")
                Divider().frame(height: 16)
                labeledRuntime("Voice", value: appState.activeVoice?.name ?? "Not set")
                Divider().frame(height: 16)
                labeledRuntime("Diagnostics", value: "\(appState.diagnosticsMessages.count)")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            card(title: "Runtime", subtitle: "Current status and clipboard") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("State: \(statusLabel)")
                    Text("Last clipboard")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(appState.lastClipboardPreview)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }
            }

            card(title: "Keyboard Shortcuts", subtitle: "Use the global shortcut from any app") {
                KeyboardShortcutReference(appState: appState)
            }

            card(title: "Quick Actions", subtitle: "Control playback") {
                HStack(spacing: 8) {
                    Button("Speak Now") { Task { await appState.speakNow() } }
                        .buttonStyle(.borderedProminent)
                    Button(appState.status == .paused ? "Resume" : "Pause") { Task { await appState.pauseOrResume() } }
                    Button("Stop") { Task { await appState.stop() } }
                    Button("Skip") { Task { await appState.skip() } }
                    Button("Clear Queue") { Task { await appState.clearQueue() } }
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
            card(title: "Keyboard Shortcuts", subtitle: "Playback controls and app commands") {
                KeyboardShortcutReference(appState: appState)
            }
        }
    }

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            card(title: "Installed Models", subtitle: "English and Dutch voices, available offline") {
                if appState.localVoices.isEmpty {
                    Text("No local models installed")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Active Voice", selection: Binding(
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
                                    Button(appState.isModelRemoving(model) ? "Removing..." : "Remove Pack") {
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
            card(title: "Recent Downloadable Audio", subtitle: "Only the latest 3 keep local WAV files") {
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

            card(title: "Text History", subtitle: "Older items keep text but audio file is cleaned") {
                if appState.speechHistory.isEmpty {
                    Text("No speech history yet")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(appState.speechHistory, id: \.id) { entry in
                            HStack(alignment: .top, spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.text)
                                        .lineLimit(2)
                                    Text("\(entry.voiceName) • \(entry.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if entry.audioFilePath != nil {
                                    statusBadge("Audio kept", isGood: true)
                                } else {
                                    statusBadge("Text only", isGood: false)
                                }
                            }
                        }

                        HStack {
                            Spacer()
                            Button("Clear History") {
                                appState.clearHistoryTextOnly()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
    }

    private func card<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.18))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }

    private func statusBadge(_ title: String, isGood: Bool) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background((isGood ? Color.green : Color.gray).opacity(0.2), in: Capsule())
            .foregroundStyle((isGood ? Color.green : Color.secondary).opacity(0.95))
    }

    private func labeledRuntime(_ title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
            Text(value)
                .fontWeight(.semibold)
        }
    }

    private var statusLabel: String {
        switch appState.status {
        case .idle: return "Idle"
        case .speaking: return "Speaking"
        case .paused: return "Paused"
        case .error: return "Error"
        }
    }

    private var isErrorStatus: Bool {
        if case .error = appState.status {
            return true
        }
        return false
    }

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.07, green: 0.08, blue: 0.10),
                    Color(red: 0.10, green: 0.10, blue: 0.13),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.blue.opacity(0.18), Color.clear, Color.cyan.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .blur(radius: 38)
        }
        .ignoresSafeArea()
    }
}
