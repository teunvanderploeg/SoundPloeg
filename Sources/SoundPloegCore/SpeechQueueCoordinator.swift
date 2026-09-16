import Foundation

public actor SpeechQueueCoordinator {
    public typealias StatusHandler = @Sendable (AppStatus) -> Void
    public typealias QueueDepthHandler = @Sendable (Int) -> Void
    public typealias JobCompletionHandler = @Sendable (SpeechJob, VoiceDescriptor, TTSOutput?) -> Void

    private let ttsService: TTSService
    private let playbackEngine: AudioPlaybackEngine
    private let diagnosticsService: DiagnosticsService
    private let maxQueueDepth: Int
    private let maxChunkLength: Int

    private var jobs: [SpeechJob] = []
    private var availableVoicesByID: [String: VoiceDescriptor] = [:]
    private var processingTask: Task<Void, Never>?
    private var shouldStopCurrent = false
    private var shouldSkipCurrent = false
    private var interruptionCount = 0

    private(set) var state: AppStatus = .idle {
        didSet { onStatusChange?(state) }
    }

    private let onStatusChange: StatusHandler?
    private let onQueueDepthChange: QueueDepthHandler?
    private var onJobCompletion: JobCompletionHandler?

    public init(
        ttsService: TTSService,
        playbackEngine: AudioPlaybackEngine,
        diagnosticsService: DiagnosticsService,
        maxQueueDepth: Int = 25,
        maxChunkLength: Int = 280,
        onStatusChange: StatusHandler? = nil,
        onQueueDepthChange: QueueDepthHandler? = nil,
        onJobCompletion: JobCompletionHandler? = nil
    ) {
        self.ttsService = ttsService
        self.playbackEngine = playbackEngine
        self.diagnosticsService = diagnosticsService
        self.maxQueueDepth = maxQueueDepth
        self.maxChunkLength = maxChunkLength
        self.onStatusChange = onStatusChange
        self.onQueueDepthChange = onQueueDepthChange
        self.onJobCompletion = onJobCompletion
    }

    public func setVoices(_ voices: [VoiceDescriptor]) {
        availableVoicesByID = Dictionary(uniqueKeysWithValues: voices.map { ($0.id, $0) })
    }

    public func queueDepth() -> Int {
        jobs.count
    }

    public func currentStatus() -> AppStatus {
        state
    }

    public func enqueue(_ job: SpeechJob) throws {
        guard jobs.count < maxQueueDepth else {
            throw SoundPloegError.queueFull(max: maxQueueDepth)
        }
        jobs.append(job)
        onQueueDepthChange?(jobs.count)
    }

    public func speakNowIfIdle() {
        guard processingTask == nil, interruptionCount == 0 else { return }
        guard !jobs.isEmpty else { return }
        shouldStopCurrent = false
        shouldSkipCurrent = false
        processingTask = Task { [weak self] in
            await self?.processQueue()
        }
    }

    public func pause() async {
        guard case .speaking = state else { return }
        await playbackEngine.pause()
        state = .paused
    }

    public func resume() async {
        guard case .paused = state else { return }
        await playbackEngine.resume()
        state = .speaking
    }

    public func stop() async {
        interruptionCount += 1
        defer {
            interruptionCount -= 1
            speakNowIfIdle()
        }
        shouldStopCurrent = true
        jobs.removeAll()
        onQueueDepthChange?(0)
        processingTask?.cancel()
        await playbackEngine.stop()
        await ttsService.cancelSynthesis()
        state = .idle
    }

    public func skip() async {
        guard processingTask != nil else { return }
        interruptionCount += 1
        defer {
            interruptionCount -= 1
            speakNowIfIdle()
        }
        shouldSkipCurrent = true
        await playbackEngine.stop()
        await ttsService.cancelSynthesis()
    }

    public func clear() {
        jobs.removeAll()
        onQueueDepthChange?(0)
    }

    public func setJobCompletionHandler(_ handler: JobCompletionHandler?) {
        onJobCompletion = handler
    }

    private func processQueue() async {
        defer {
            processingTask = nil
            if case .error = state {
                // Keep error status visible until the next user action.
            } else {
                state = .idle
            }
            if !jobs.isEmpty { speakNowIfIdle() }
        }

        while !jobs.isEmpty {
            // A cancelled request may resume before Stop/Skip has finished stopping playback.
            while interruptionCount > 0 && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
            if shouldStopCurrent || Task.isCancelled {
                shouldStopCurrent = false
                break
            }

            let job = jobs.removeFirst()
            onQueueDepthChange?(jobs.count)

            guard let voice = availableVoicesByID[job.voiceID] else {
                await diagnosticsService.publish(ErrorMapper.map(SoundPloegError.unavailableVoice(job.voiceID)))
                continue
            }

            state = .speaking

            shouldSkipCurrent = false
            var next: Task<TTSOutput, Error>?
            do {
                let chunks = Self.chunkedText(job.text, maxChunkLength: maxChunkLength)
                var firstOutput: TTSOutput?
                var completedAllChunks = true
                defer { next?.cancel() }
                for (index, chunk) in chunks.enumerated() {
                    try Task.checkCancellation()
                    if shouldStopCurrent || shouldSkipCurrent {
                        completedAllChunks = false
                        break
                    }
                    let output: TTSOutput
                    if let prefetched = next {
                        output = try await prefetched.value
                        next = nil
                    } else {
                        output = try await ttsService.synthesize(text: chunk, voice: voice, rate: job.rate)
                    }
                    if chunks.count > 1 {
                        // This chunk has no history export; remove it after playback or interruption.
                        firstOutput = nil
                    } else {
                        firstOutput = output
                    }
                    do {
                        try Task.checkCancellation()
                        if shouldStopCurrent || shouldSkipCurrent { throw CancellationError() }
                        while state == .paused {
                            try await Task.sleep(nanoseconds: 50_000_000)
                            if shouldStopCurrent || shouldSkipCurrent { throw CancellationError() }
                        }
                        // Prepare the next chunk while this one plays, using the same resident model.
                        if index + 1 < chunks.count {
                            let text = chunks[index + 1]
                            next = Task { [ttsService] in
                                let result = try await ttsService.synthesize(text: text, voice: voice, rate: job.rate)
                                if Task.isCancelled {
                                    Self.removeTemporaryAudio(result)
                                    throw CancellationError()
                                }
                                return result
                            }
                        }
                        try await playbackEngine.play(output: output)
                        if chunks.count > 1 { Self.removeTemporaryAudio(output) }
                        if shouldStopCurrent || shouldSkipCurrent {
                            completedAllChunks = false
                            break
                        }
                    } catch {
                        Self.removeTemporaryAudio(output)
                        throw error
                    }
                }
                if completedAllChunks {
                    onJobCompletion?(job, voice, firstOutput)
                } else {
                    await discardPrefetchedAudio(next)
                    if let firstOutput { Self.removeTemporaryAudio(firstOutput) }
                }
            } catch is CancellationError {
                await discardPrefetchedAudio(next)
                // Stop and skip are deliberate, never reasons to invoke a fallback voice.
            } catch {
                await discardPrefetchedAudio(next)
                let mapped = ErrorMapper.map(error)
                await diagnosticsService.publish(mapped)
                state = .error(mapped)
            }
            if shouldStopCurrent || Task.isCancelled { break }
        }
    }

    private func discardPrefetchedAudio(_ task: Task<TTSOutput, Error>?) async {
        guard let task else { return }
        task.cancel()
        if let abandoned = try? await task.value { Self.removeTemporaryAudio(abandoned) }
    }

    private static func removeTemporaryAudio(_ output: TTSOutput) {
        if case .audioFile(let url) = output,
           url.lastPathComponent.hasPrefix("soundploeg-") {
            try? FileManager.default.removeItem(at: url)
        }
    }

    static func chunkedText(_ text: String, maxChunkLength: Int) -> [String] {
        // Preserve punctuation and words. Prefer a sentence boundary, then whitespace.
        let limit = max(1, maxChunkLength)
        var remaining = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var chunks: [String] = []
        while remaining.count > limit {
            let end = remaining.index(remaining.startIndex, offsetBy: limit)
            let prefix = remaining[..<end]
            let sentenceBoundary = prefix.indices.last { index in
                guard ".!?;\n".contains(prefix[index]) else { return false }
                let after = remaining.index(after: index)
                return after == remaining.endIndex || remaining[after].isWhitespace
            }
            let split: String.Index
            if let sentenceBoundary { split = remaining.index(after: sentenceBoundary) }
            else { split = prefix.lastIndex(where: { $0.isWhitespace }) ?? end }
            if split == remaining.startIndex {
                remaining = String(remaining.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }
            chunks.append(String(remaining[..<split]).trimmingCharacters(in: .whitespacesAndNewlines))
            remaining = String(remaining[split...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if !remaining.isEmpty { chunks.append(remaining) }
        return chunks
    }
}
