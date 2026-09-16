import CryptoKit
import Foundation
import SoundPloegCore

public actor ModelLibraryService {
    private let modelRootURL: URL
    private let fileManager: FileManager
    private let urlSession: URLSession
    private var busy: Set<String> = []

    public init(modelRootURL: URL, fileManager: FileManager = .default, urlSession: URLSession = .shared) {
        self.modelRootURL = modelRootURL
        self.fileManager = fileManager
        self.urlSession = urlSession
    }

    public func catalog() throws -> [DownloadableModel] { try VoiceCatalog.loadDownloadableModels() }

    public func installedVoices() throws -> [VoiceDescriptor] {
        try VoiceCatalog.scanInstalledVoices(modelRoot: modelRootURL, fileManager: fileManager)
    }

    public func download(model: DownloadableModel) async throws {
        guard try catalog().contains(model) else { throw SoundPloegError.unknown("Unknown model pack") }
        guard busy.insert(model.id).inserted else { return }
        defer { busy.remove(model.id) }
        if VoiceCatalog.isInstalled(model, root: modelRootURL, fileManager: fileManager) { return }
        try fileManager.createDirectory(at: modelRootURL, withIntermediateDirectories: true)
        let staging = modelRootURL.appendingPathComponent(".download-\(UUID().uuidString)")
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }
        for asset in model.files {
            try Task.checkCancellation()
            guard let url = URL(string: asset.url), url.scheme == "https",
                  !asset.path.hasPrefix("/"), !asset.path.split(separator: "/").contains("..") else {
                throw SoundPloegError.unknown("Invalid model asset")
            }
            let (temp, response) = try await urlSession.download(from: url)
            defer { try? fileManager.removeItem(at: temp) }
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw SoundPloegError.unknown("Download failed for \(asset.path). Try again.")
            }
            try Self.verify(temp, asset: asset)
            let destination = staging.appendingPathComponent(asset.path)
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.moveItem(at: temp, to: destination)
        }
        try JSONEncoder().encode(model).write(to: staging.appendingPathComponent("installed.json"), options: .atomic)
        let destination = modelRootURL.appendingPathComponent(model.id)
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: staging)
        } else {
            try fileManager.moveItem(at: staging, to: destination)
        }
    }

    public func remove(model: DownloadableModel) throws {
        guard try catalog().contains(model), !busy.contains(model.id) else {
            throw SoundPloegError.unknown("Model pack is busy or unknown")
        }
        let destination = modelRootURL.appendingPathComponent(model.id)
        if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
    }

    static func verify(_ url: URL, asset: ModelAsset) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        var size: Int64 = 0
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            size += Int64(data.count)
            hash.update(data: data)
        }
        let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard size == asset.bytes, digest == asset.sha256 else {
            throw SoundPloegError.unknown("Integrity check failed for \(asset.path). Download the model again.")
        }
    }
}
