import Foundation
import SoundPloegCore

/// One request at a time over pipes. No listening port, network requests, or per-chunk process launch.
actor SpeechWorker {
    private let python: URL
    private let script: URL
    private let timeoutSeconds: UInt64
    private var process: Process?
    private var input: FileHandle?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var buffer = Data()
    private var stderr = ""
    private var generation = UUID()
    private var pending: (UUID, CheckedContinuation<Void, Error>)?
    private var timeout: Task<Void, Never>?

    init(python: URL, script: URL, timeoutSeconds: UInt64 = 90) {
        self.python = python
        self.script = script
        self.timeoutSeconds = timeoutSeconds
    }

    deinit {
        timeout?.cancel()
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        try? input?.close()
        if let process, process.isRunning { process.terminate() }
    }

    func request(_ fields: [String: Any]) async throws {
        try Task.checkCancellation()
        guard pending == nil else { throw SoundPloegError.synthesisFailed("Speech worker is busy") }
        try startIfNeeded()
        let id = UUID()
        var payload = fields
        payload["id"] = id.uuidString
        var data = try JSONSerialization.data(withJSONObject: payload)
        data.append(10)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending = (id, continuation)
                timeout = Task { [weak self, timeoutSeconds] in
                    do { try await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000) }
                    catch { return }
                    await self?.expire(id)
                }
                do { try input?.write(contentsOf: data) }
                catch { stop(error: error) }
            }
        } onCancel: {
            Task { await self.cancel(id: id) }
        }
    }

    func cancel() { stop(error: CancellationError()) }

    private func cancel(id: UUID) {
        if pending?.0 == id { cancel() }
    }

    private func expire(_ id: UUID) {
        if pending?.0 == id { stop(error: SoundPloegError.synthesisFailed("Speech generation timed out. Try a shorter passage.")) }
    }

    private func startIfNeeded() throws {
        if let process, process.isRunning { return }
        guard FileManager.default.isExecutableFile(atPath: python.path) else {
            throw SoundPloegError.pythonRuntimeMissing(python.path)
        }
        guard FileManager.default.fileExists(atPath: script.path) else {
            throw SoundPloegError.synthesisFailed("Bundled speech worker is missing")
        }
        let process = Process()
        let stdin = Pipe(), stdout = Pipe(), errors = Pipe()
        let token = UUID()
        generation = token
        buffer.removeAll()
        stderr = ""
        process.executableURL = python
        process.arguments = ["-B", "-u", script.path]
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = errors
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty { Task { await self?.received(data, token: token) } }
        }
        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty { Task { await self?.receivedError(data, token: token) } }
        }
        process.terminationHandler = { [weak self] process in
            Task { await self?.exited(process.terminationStatus, token: token) }
        }
        self.process = process
        input = stdin.fileHandleForWriting
        outputPipe = stdout
        errorPipe = errors
        do { try process.run() }
        catch { stop(error: error); throw error }
    }

    private func receivedError(_ data: Data, token: UUID) {
        guard token == generation else { return }
        stderr = String((stderr + String(decoding: data, as: UTF8.self)).suffix(4000))
    }

    private func received(_ data: Data, token: UUID) {
        guard token == generation else { return }
        buffer.append(data)
        guard buffer.count <= 65536 else {
            stop(error: SoundPloegError.synthesisFailed("Invalid worker response")); return
        }
        while let newline = buffer.firstIndex(of: 10) {
            let line = buffer.prefix(upTo: newline)
            buffer.removeSubrange(...newline)
            guard let response = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let id = response["id"] as? String, id == pending?.0.uuidString else {
                stop(error: SoundPloegError.synthesisFailed("Invalid worker response")); return
            }
            if response["ok"] as? Bool == true { finish(.success(())) }
            else { finish(.failure(SoundPloegError.synthesisFailed(response["error"] as? String ?? "Unknown worker failure"))) }
        }
    }

    private func exited(_ status: Int32, token: UUID) {
        guard token == generation else { return }
        stop(error: SoundPloegError.synthesisFailed("Speech worker exited (\(status)). \(stderr)"))
    }

    private func finish(_ result: Result<Void, Error>) {
        timeout?.cancel()
        timeout = nil
        let continuation = pending?.1
        pending = nil
        continuation?.resume(with: result)
    }

    private func stop(error: Error) {
        generation = UUID()
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        try? input?.close()
        if let process, process.isRunning { process.terminate() }
        process = nil
        input = nil
        outputPipe = nil
        errorPipe = nil
        buffer.removeAll()
        finish(.failure(error))
    }
}
