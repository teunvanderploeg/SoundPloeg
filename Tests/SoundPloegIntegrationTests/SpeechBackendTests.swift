import AVFoundation
import XCTest
import SoundPloegCore
@testable import SoundPloegInfra

final class SpeechBackendTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    func testCatalogProvidesEnglishAndDutchWithoutLegacyModels() throws {
        let packs = try VoiceCatalog.loadDownloadableModels()
        XCTAssertEqual(Set(packs.map(\.engine)), ["kokoro", "supertonic"])
        XCTAssertEqual(packs.flatMap(\.voices).count, 6)
        for pack in packs {
            XCTAssertFalse(pack.files.isEmpty)
            for file in pack.files {
                XCTAssertTrue(file.url.contains(pack.revision))
                XCTAssertEqual(file.sha256.count, 64)
                XCTAssertGreaterThan(file.bytes, 0)
            }
        }
        let root = try temporaryDirectory()
        XCTAssertTrue(try VoiceCatalog.scanInstalledVoices(modelRoot: root).isEmpty)
        // Orphaned old ONNX files must not be advertised as usable new voices.
        try Data([1]).write(to: root.appendingPathComponent("en_US-lessac-low.onnx"))
        XCTAssertTrue(try VoiceCatalog.scanInstalledVoices(modelRoot: root).isEmpty)
    }

    func testChecksumRejectsCorruptedDownload() throws {
        let root = try temporaryDirectory()
        let file = root.appendingPathComponent("asset")
        let asset = try JSONDecoder().decode(ModelAsset.self, from: Data("""
        {"path":"asset","url":"https://example.com/asset","bytes":3,"sha256":"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"}
        """.utf8))
        try Data("abc".utf8).write(to: file)
        XCTAssertNoThrow(try ModelLibraryService.verify(file, asset: asset))
        try Data("abd".utf8).write(to: file)
        XCTAssertThrowsError(try ModelLibraryService.verify(file, asset: asset))
    }

    private func fixtureWorker(timeout: UInt64 = 5) throws -> (SpeechWorker, URL) {
        let root = try temporaryDirectory()
        let script = root.appendingPathComponent("worker.py")
        try """
        import json, os, sys, time
        for line in sys.stdin:
            request = json.loads(line)
            if request.get('op') == 'hang': time.sleep(10)
            if request.get('op') == 'crash': sys.exit(3)
            if request.get('path'):
                with open(request['path'], 'a') as f: f.write(str(os.getpid())+'\\n')
            print(json.dumps({'id': request['id'], 'ok': True}), flush=True)
        """.write(to: script, atomically: true, encoding: .utf8)
        return (SpeechWorker(python: URL(fileURLWithPath: "/usr/bin/python3"), script: script, timeoutSeconds: timeout), root)
    }

    func testWorkerReusesProcessAndRestartsAfterCrash() async throws {
        let (worker, root) = try fixtureWorker()
        let log = root.appendingPathComponent("pids")
        try await worker.request(["path": log.path])
        try await worker.request(["path": log.path])
        let first = try String(contentsOf: log).split(separator: "\n")
        XCTAssertEqual(first.count, 2)
        XCTAssertEqual(first[0], first[1])
        do {
            try await worker.request(["op": "crash"])
            XCTFail("Expected worker failure")
        } catch {}
        try await worker.request(["path": log.path])
        let all = try String(contentsOf: log).split(separator: "\n")
        XCTAssertNotEqual(all.first, all.last)
        await worker.cancel()
    }

    func testWorkerTimeoutAndCancellationPermitNextRequest() async throws {
        let (worker, _) = try fixtureWorker(timeout: 1)
        do {
            try await worker.request(["op": "hang"])
            XCTFail("Expected timeout")
        } catch { XCTAssertTrue(error.localizedDescription.contains("timed out")) }
        try await worker.request([:])
        let task = Task { try await worker.request(["op": "hang"]) }
        try await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        do { try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        try await worker.request([:])
        await worker.cancel()
    }

    func testRealEnglishAndDutchSynthesisWhenConfigured() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let root = env["SOUNDPLOEG_TEST_MODEL_ROOT"],
              let python = env["SOUNDPLOEG_TEST_PYTHON"] else {
            throw XCTSkip("Set SOUNDPLOEG_TEST_MODEL_ROOT and SOUNDPLOEG_TEST_PYTHON for real inference")
        }
        let service = LocalTTSService(pythonExecutableURL: URL(fileURLWithPath: python), modelRootURL: URL(fileURLWithPath: root))
        let voices = try await service.availableVoices()
        XCTAssertEqual(voices.count, 6)
        for (id, text, sampleRate) in [
            ("kokoro-af-heart", "This is a real English speech test.", 24000.0),
            ("supertonic-nl-f1", "Dit is een echte Nederlandse spraaktest.", 44100.0)
        ] {
            let voice = try XCTUnwrap(voices.first { $0.id == id })
            let output = try await service.synthesize(text: text, voice: voice, rate: 1)
            guard case .audioFile(let url) = output else { return XCTFail("Expected local WAV") }
            defer { try? FileManager.default.removeItem(at: url) }
            let file = try AVAudioFile(forReading: url)
            XCTAssertEqual(file.processingFormat.sampleRate, sampleRate)
            XCTAssertGreaterThan(file.length, AVAudioFramePosition(sampleRate))
        }
        await service.cancelSynthesis()
    }

    func testBundledRuntimeIsPresent() {
        XCTAssertNotNil(VoiceCatalog.resourceBundle.url(forResource: "tts_worker", withExtension: "py", subdirectory: "Runtime"))
        XCTAssertNotNil(VoiceCatalog.resourceBundle.url(forResource: "supertonic_inference", withExtension: "py", subdirectory: "Runtime"))
    }
}
