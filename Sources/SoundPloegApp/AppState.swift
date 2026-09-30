import AppKit
import Foundation
import SoundPloegCore
import SoundPloegInfra

@MainActor
final class AppState: ObservableObject {
    @Published var status: AppStatus = .idle
    @Published var lastClipboardPreview: String = "No clipboard text yet."
    @Published var queueDepth: Int = 0
    @Published var currentSpeech: CurrentSpeech?
    @Published var activeVoice: VoiceDescriptor?
    @Published var availableVoices: [VoiceDescriptor] = []
    @Published var speechRate: Float
    @Published var autoSpeakOnHotkey: Bool
    @Published private(set) var hotkeyShortcut: HotkeyShortcut
    @Published var diagnosticsMessages: [UserMessage] = []
    @Published var latestMessage: UserMessage?

    @Published var downloadableModels: [DownloadableModel] = []
    @Published var installedModelIDs: Set<String> = []
    @Published var downloadingModelIDs: Set<String> = []
    @Published var removingModelIDs: Set<String> = []
    @Published var speechHistory: [SpeechHistoryEntry] = []

    private let settingsStore: SettingsStore

    var localVoices: [VoiceDescriptor] {
        availableVoices.filter { !$0.isSystem }
    }

    private let historyAudioDirectoryURL: URL
    private let modelLibrary: ModelLibraryService
    private let diagnosticsService: InMemoryDiagnosticsService
    private let clipboardService: ClipboardService
    private let hotkeyService: HotkeyService
    private let queueCoordinator: SpeechQueueCoordinator
    private let ttsService: TTSService

    private var hotkeyTask: Task<Void, Never>?
    private var stateTask: Task<Void, Never>?

    private let maxStoredAudioHistoryFiles = 3
    private let maxHistoryEntries = 100

    private lazy var hotkeyIngestionCoordinator: HotkeyIngestionCoordinator = {
        HotkeyIngestionCoordinator(
            clipboardService: clipboardService,
            queueCoordinator: queueCoordinator,
            previewHandler: { [weak self] preview in
                Task { @MainActor in
                    self?.lastClipboardPreview = preview
                }
            }
        )
    }()

    init(
        settings: SettingsStore = UserDefaultsSettingsStore(),
        clipboard: ClipboardService = NSPasteboardClipboardService(),
        queue: SpeechQueueCoordinator? = nil,
        appSupportURL: URL? = nil,
        startsAutomatically: Bool = true
    ) {
        let diagnostics = InMemoryDiagnosticsService()
        let hotkey = CarbonHotkeyService()

        let appSupport = appSupportURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("SoundPloeg", isDirectory: true)
        let defaultModelRoot = appSupport.appendingPathComponent("models", isDirectory: true)
        let historyAudioDirectoryURL = appSupport.appendingPathComponent("history_audio", isDirectory: true)
        let modelRoot = URL(fileURLWithPath: settings.preferredModelRootPath ?? defaultModelRoot.path)
        let pythonURL = appSupport.appendingPathComponent("tts-venv/bin/python", isDirectory: false)

        let modelLibrary = ModelLibraryService(modelRootURL: modelRoot)
        let local = LocalTTSService(
            pythonExecutableURL: pythonURL,
            modelRootURL: modelRoot
        )
        let system = SystemTTSService()
        let composite = CompositeTTSService(local: local, system: system, diagnostics: diagnostics)
        let queue = queue ?? SpeechQueueCoordinator(
            ttsService: composite,
            playbackEngine: AVAudioPlaybackEngine(),
            diagnosticsService: diagnostics
        )

        self.settingsStore = settings
        self.historyAudioDirectoryURL = historyAudioDirectoryURL
        self.modelLibrary = modelLibrary
        self.diagnosticsService = diagnostics
        self.clipboardService = clipboard
        self.hotkeyService = hotkey
        self.ttsService = composite
        self.queueCoordinator = queue
        self.speechRate = settings.speechRate
        self.autoSpeakOnHotkey = settings.autoSpeakOnHotkey
        self.hotkeyShortcut = settings.hotkeyShortcut
        loadSpeechHistoryFromSettings()

        if startsAutomatically {
            Task { [weak self, queueCoordinator] in
                await queueCoordinator.setJobCompletionHandler { [weak self] job, voice, output in
                    Task { @MainActor in
                        await self?.handleCompletedJob(job: job, voice: voice, output: output)
                    }
                }
                await self?.bootstrap()
            }
        }
    }

    deinit {
        hotkeyTask?.cancel()
        stateTask?.cancel()
    }

    func bootstrap() async {
        await registerHotkey()
        await refreshModelLibraryState()
        await loadVoices()
        await startHotkeyListener()
        await startStatePoller()
        await refreshDiagnostics()
    }

    func loadVoices() async {
        do {
            let voices = try await ttsService.availableVoices()
            availableVoices = voices.sorted { lhs, rhs in
                if lhs.language == rhs.language {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.language.localizedCaseInsensitiveCompare(rhs.language) == .orderedAscending
            }

            activeVoice = resolveActiveVoice(from: voices)
            if let activeVoice {
                settingsStore.selectedVoiceID = activeVoice.id
            }

            installedModelIDs = Set(downloadableModels.filter { model in
                model.voices.allSatisfy { entry in voices.contains { $0.id == entry.id } }
            }.map(\.id))
            await queueCoordinator.setVoices(voices)
            await ttsService.warmUp()
        } catch {
            let mapped = ErrorMapper.map(error)
            latestMessage = mapped
            await diagnosticsService.publish(mapped)
        }
    }

    func refreshModelLibraryState() async {
        do {
            downloadableModels = try await modelLibrary.catalog()
            let installed = try await modelLibrary.installedVoices()
            installedModelIDs = Set(downloadableModels.filter { model in
                model.voices.allSatisfy { entry in installed.contains { $0.id == entry.id } }
            }.map(\.id))
        } catch {
            let mapped = ErrorMapper.map(error)
            latestMessage = mapped
            await diagnosticsService.publish(mapped)
        }
    }

    func downloadModel(_ model: DownloadableModel) async {
        guard !downloadingModelIDs.contains(model.id) else { return }

        downloadingModelIDs.insert(model.id)
        defer { downloadingModelIDs.remove(model.id) }

        do {
            try await modelLibrary.download(model: model)
            latestMessage = UserMessage(
                title: "Model Downloaded",
                detail: "\(model.name) is now available.",
                severity: .info
            )
            await refreshModelLibraryState()
            await loadVoices()
        } catch {
            let mapped = ErrorMapper.map(error)
            latestMessage = mapped
            await diagnosticsService.publish(mapped)
        }
    }

    func removeModel(_ model: DownloadableModel) async {
        guard !removingModelIDs.contains(model.id) else { return }

        removingModelIDs.insert(model.id)
        defer { removingModelIDs.remove(model.id) }

        do {
            await queueCoordinator.stop()
            try await modelLibrary.remove(model: model)
            latestMessage = UserMessage(
                title: "Model Removed",
                detail: "\(model.name) was removed from local storage.",
                severity: .info
            )
            await refreshModelLibraryState()
            await loadVoices()
        } catch {
            let mapped = ErrorMapper.map(error)
            latestMessage = mapped
            await diagnosticsService.publish(mapped)
        }
    }

    func useModel(_ model: DownloadableModel) {
        guard let voice = availableVoices.first(where: { voice in model.voices.contains { $0.id == voice.id } && !voice.isSystem }) else {
            latestMessage = UserMessage(
                title: "Model Not Installed",
                detail: "Download \(model.name) first.",
                severity: .warning
            )
            return
        }

        setVoice(voice)
        latestMessage = UserMessage(
            title: "Model Selected",
            detail: "Using \(model.name) for local speech.",
            severity: .info
        )
    }

    func isModelInstalled(_ model: DownloadableModel) -> Bool {
        installedModelIDs.contains(model.id)
    }

    func isModelDownloading(_ model: DownloadableModel) -> Bool {
        downloadingModelIDs.contains(model.id)
    }

    func isModelRemoving(_ model: DownloadableModel) -> Bool {
        removingModelIDs.contains(model.id)
    }

    func downloadableModel(for voice: VoiceDescriptor) -> DownloadableModel? {
        downloadableModels.first(where: { $0.voices.contains { $0.id == voice.id } })
    }

    func registerHotkey() async {
        do {
            try hotkeyService.register(shortcut: hotkeyShortcut)
        } catch {
            let mapped = ErrorMapper.map(error)
            latestMessage = mapped
            await diagnosticsService.publish(mapped)
        }
    }

    func updateHotkey(_ shortcut: HotkeyShortcut) async {
        let previous = hotkeyShortcut
        do {
            try hotkeyService.register(shortcut: shortcut)
            settingsStore.hotkeyShortcut = shortcut
            hotkeyShortcut = shortcut
        } catch {
            // Registering a new Carbon shortcut releases the old registration first.
            try? hotkeyService.register(shortcut: previous)
            let message = ErrorMapper.map(error)
            latestMessage = message
            await diagnosticsService.publish(message)
        }
    }

    func startHotkeyListener() async {
        hotkeyTask?.cancel()
        hotkeyTask = Task {
            for await _ in hotkeyService.eventStream() {
                guard let selectedVoice = await MainActor.run(body: { activeVoice }) else { continue }
                let rate = await MainActor.run(body: { speechRate })
                let auto = await MainActor.run(body: { autoSpeakOnHotkey })

                if let message = await hotkeyIngestionCoordinator.handleHotkey(
                    selectedVoice: selectedVoice,
                    rate: rate,
                    autoSpeakOnHotkey: auto
                ) {
                    await diagnosticsService.publish(message)
                    await MainActor.run {
                        latestMessage = message
                    }
                }
            }
        }
    }

    func startStatePoller() async {
        stateTask?.cancel()
        stateTask = Task {
            while !Task.isCancelled {
                let snapshot = await queueCoordinator.snapshot()
                let diagnostics = await diagnosticsService.messages()

                await MainActor.run {
                    self.applySnapshot(snapshot)
                    if self.diagnosticsMessages != diagnostics {
                        self.diagnosticsMessages = diagnostics
                        if let message = diagnostics.last { self.latestMessage = message }
                    }
                }

                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }
    }

    func speakNow() async {
        guard let selectedVoice = activeVoice else {
            let message = UserMessage(
                title: "No Active Voice",
                detail: "Install/select a local model first.",
                severity: .warning
            )
            latestMessage = message
            await diagnosticsService.publish(message)
            return
        }

        if let message = await hotkeyIngestionCoordinator.handleHotkey(
            selectedVoice: selectedVoice,
            rate: speechRate,
            autoSpeakOnHotkey: true
        ) {
            latestMessage = message
            await diagnosticsService.publish(message)
        }
    }

    func pauseOrResume() async {
        switch status {
        case .speaking:
            await queueCoordinator.pause()
        case .paused:
            await queueCoordinator.resume()
        default:
            break
        }
    }

    private func applySnapshot(_ snapshot: SpeechQueueSnapshot) {
        if status != snapshot.status { status = snapshot.status }
        if queueDepth != snapshot.queueDepth { queueDepth = snapshot.queueDepth }
        if currentSpeech != snapshot.currentSpeech { currentSpeech = snapshot.currentSpeech }
    }

    var statusLabel: String {
        switch status {
        case .idle: return "Idle"
        case .speaking: return currentSpeech?.phase == .preparing ? "Preparing speech" : "Playing"
        case .paused: return "Paused"
        case .error: return "Error"
        }
    }

    func canPerform(_ action: SpeechAction) -> Bool {
        switch action {
        case .speak: return activeVoice != nil
        case .playQueue: return queueDepth > 0 && currentSpeech == nil
        case .pause: return status == .speaking || status == .paused
        case .stop: return currentSpeech != nil || queueDepth > 0
        case .skip: return currentSpeech != nil
        case .clear: return queueDepth > 0
        }
    }

    func playQueue() async {
        await queueCoordinator.speakNowIfIdle()
        applySnapshot(await queueCoordinator.snapshot())
    }

    func stop() async {
        await queueCoordinator.stop()
    }

    func skip() async {
        await queueCoordinator.skip()
    }

    func clearQueue() async {
        await queueCoordinator.clear()
    }

    func perform(_ action: SpeechAction) async {
        switch action {
        case .speak: await speakNow()
        case .playQueue: await playQueue()
        case .pause: await pauseOrResume()
        case .stop: await stop()
        case .skip: await skip()
        case .clear: await clearQueue()
        }
        applySnapshot(await queueCoordinator.snapshot())
    }

    func previewVoice(_ voice: VoiceDescriptor) async {
        let text = voice.language.hasPrefix("nl")
            ? "Hallo! Dit is een voorbeeld van de Nederlandse stem."
            : "Hello! This is a preview of the English voice."
        do {
            try await queueCoordinator.enqueue(SpeechJob(text: text, voiceID: voice.id, rate: speechRate))
            await queueCoordinator.speakNowIfIdle()
        } catch {
            let message = ErrorMapper.map(error)
            latestMessage = message
            await diagnosticsService.publish(message)
        }
    }

    func setVoice(_ voice: VoiceDescriptor) {
        activeVoice = voice
        settingsStore.selectedVoiceID = voice.id
    }

    func setRate(_ rate: Float) {
        speechRate = rate
        settingsStore.speechRate = rate
    }

    func setAutoSpeak(_ enabled: Bool) {
        autoSpeakOnHotkey = enabled
        settingsStore.autoSpeakOnHotkey = enabled
    }

    func refreshDiagnostics() async {
        diagnosticsMessages = await diagnosticsService.messages()
    }

    var recentHistoryWithAudio: [SpeechHistoryEntry] {
        speechHistory.filter { $0.audioFilePath != nil }.prefix(maxStoredAudioHistoryFiles).map { $0 }
    }

    func replayHistory(_ entry: SpeechHistoryEntry, useCurrentVoice: Bool = false) async {
        let voice = useCurrentVoice ? activeVoice : availableVoices.first { $0.id == entry.voiceID }
        guard let voice else {
            latestMessage = UserMessage(title: "Voice Unavailable", detail: "Install the original voice pack, or choose Replay with current voice.", severity: .warning)
            return
        }
        do {
            try await queueCoordinator.enqueue(SpeechJob(text: entry.text, voiceID: voice.id,
                                                        rate: useCurrentVoice ? speechRate : entry.rate))
            await queueCoordinator.speakNowIfIdle()
            applySnapshot(await queueCoordinator.snapshot())
            latestMessage = UserMessage(title: "Replay Queued", detail: "Reading with \(voice.name).", severity: .info)
        } catch {
            let message = ErrorMapper.map(error)
            latestMessage = message
            await diagnosticsService.publish(message)
        }
    }

    func copyHistoryText(_ entry: SpeechHistoryEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)
        latestMessage = UserMessage(title: "Text Copied", detail: "The full reading is on your clipboard.", severity: .info)
    }

    func deleteHistoryEntry(_ entry: SpeechHistoryEntry) {
        let audioURL = historyAudioURL(for: entry)
        speechHistory.removeAll { $0.id == entry.id }
        persistSpeechHistory()
        if let audioURL {
            Task.detached { try? FileManager.default.removeItem(at: audioURL) }
        }
        latestMessage = UserMessage(title: "History Item Deleted", detail: "Removed the text and any saved audio for this item.", severity: .info)
    }

    func exportHistoryAudio(_ entry: SpeechHistoryEntry) {
        guard let sourceURL = historyAudioURL(for: entry) else {
            latestMessage = UserMessage(
                title: "Audio Missing",
                detail: "This history item no longer has a saved audio file.",
                severity: .warning
            )
            return
        }

        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.allowedContentTypes = [.wav]
        savePanel.nameFieldStringValue = "soundploeg-\(entry.id.uuidString.prefix(8)).wav"

        guard savePanel.runModal() == .OK, let destinationURL = savePanel.url else { return }

        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            latestMessage = UserMessage(
                title: "Audio Exported",
                detail: "Saved to \(destinationURL.lastPathComponent).",
                severity: .info
            )
        } catch {
            latestMessage = UserMessage(
                title: "Export Failed",
                detail: error.localizedDescription,
                severity: .error
            )
        }
    }

    func clearHistoryTextOnly() {
        let fileURLsToDelete = speechHistory.compactMap(historyAudioURL(for:))
        speechHistory.removeAll()
        persistSpeechHistory()
        Task.detached {
            for fileURL in fileURLsToDelete {
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
    }

    private func resolveActiveVoice(from voices: [VoiceDescriptor]) -> VoiceDescriptor? {
        let local = voices.filter { !$0.isSystem }

        if let selectedID = settingsStore.selectedVoiceID,
           let match = local.first(where: { $0.id == selectedID }) {
            return match
        }

        if settingsStore.selectedVoiceID?.contains("-nl-") == true,
           let dutch = local.first(where: { $0.language.hasPrefix("nl") }) { return dutch }

        if let englishLocal = local.first(where: { $0.language.hasPrefix("en") }) {
            return englishLocal
        }

        if let dutchLocal = local.first(where: { $0.language.hasPrefix("nl") }) {
            return dutchLocal
        }

        return local.first ?? voices.first(where: { $0.language.hasPrefix("en") }) ?? voices.first
    }

    private func loadSpeechHistoryFromSettings() {
        guard let raw = settingsStore.speechHistoryData else { return }

        do {
            speechHistory = try JSONDecoder().decode([SpeechHistoryEntry].self, from: raw)
        } catch {
            speechHistory = []
            settingsStore.speechHistoryData = nil
        }
    }

    private func persistSpeechHistory() {
        do {
            settingsStore.speechHistoryData = try JSONEncoder().encode(speechHistory)
        } catch {
            settingsStore.speechHistoryData = nil
        }
    }

    private func historyAudioURL(for entry: SpeechHistoryEntry) -> URL? {
        guard let path = entry.audioFilePath else { return nil }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    private func appendHistoryEntry(_ entry: SpeechHistoryEntry) {
        var updated = [entry] + speechHistory
        if updated.count > maxHistoryEntries {
            updated = Array(updated.prefix(maxHistoryEntries))
        }

        var filesToDelete: [URL] = []
        var retainedAudioCount = 0
        for index in updated.indices {
            guard let path = updated[index].audioFilePath else { continue }
            retainedAudioCount += 1
            if retainedAudioCount > maxStoredAudioHistoryFiles {
                let url = URL(fileURLWithPath: path)
                filesToDelete.append(url)
                updated[index].audioFilePath = nil
            }
        }

        speechHistory = updated
        persistSpeechHistory()

        guard !filesToDelete.isEmpty else { return }
        Task.detached {
            for url in filesToDelete {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private func persistAudioForHistory(from sourceURL: URL, job: SpeechJob) async -> URL? {
        await Task.detached(priority: .utility) { [historyAudioDirectoryURL] in
            do {
                try FileManager.default.createDirectory(at: historyAudioDirectoryURL, withIntermediateDirectories: true)
                let destinationURL = historyAudioDirectoryURL.appendingPathComponent("\(job.id.uuidString).wav")
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                return destinationURL
            } catch {
                return nil
            }
        }.value
    }

    private func handleCompletedJob(job: SpeechJob, voice: VoiceDescriptor, output: TTSOutput?) async {
        var audioFilePath: String?
        if case .audioFile(let sourceURL) = output {
            let storedURL = await persistAudioForHistory(from: sourceURL, job: job)
            audioFilePath = storedURL?.path
            try? FileManager.default.removeItem(at: sourceURL)
        }

        let entry = SpeechHistoryEntry(
            id: job.id,
            createdAt: Date(),
            text: job.text,
            voiceID: voice.id,
            voiceName: voice.name,
            rate: job.rate,
            audioFilePath: audioFilePath
        )
        appendHistoryEntry(entry)
    }
}
