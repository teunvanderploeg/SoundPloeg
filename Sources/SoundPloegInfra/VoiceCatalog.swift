import Foundation
import SoundPloegCore

struct VoiceCatalog {
    static var resourceBundle: Bundle {
#if SWIFT_PACKAGE
        return .module
#else
        return Bundle(for: BundleToken.self)
#endif
    }

    static func loadDownloadableModels() throws -> [DownloadableModel] {
        guard let url = resourceBundle.url(forResource: "model_catalog", withExtension: "json") else {
            throw SoundPloegError.unknown("Missing model catalog resource")
        }
        return try JSONDecoder().decode([DownloadableModel].self, from: Data(contentsOf: url))
    }

    static func isInstalled(_ model: DownloadableModel, root: URL, fileManager: FileManager = .default) -> Bool {
        let directory = root.appendingPathComponent(model.id)
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("installed.json")),
              let installed = try? JSONDecoder().decode(DownloadableModel.self, from: data),
              installed == model else { return false }
        return model.files.allSatisfy { asset in
            let path = directory.appendingPathComponent(asset.path).path
            guard let attributes = try? fileManager.attributesOfItem(atPath: path),
                  let size = attributes[.size] as? NSNumber else { return false }
            return size.int64Value == asset.bytes
        }
    }

    static func scanInstalledVoices(modelRoot: URL, fileManager: FileManager = .default) throws -> [VoiceDescriptor] {
        try loadDownloadableModels().filter {
            isInstalled($0, root: modelRoot, fileManager: fileManager)
        }.flatMap { model in
            model.voices.map { voice in
                VoiceDescriptor(id: voice.id, name: voice.name, language: voice.language,
                    modelPath: modelRoot.appendingPathComponent(model.id).path,
                    configPath: modelRoot.appendingPathComponent(model.id).appendingPathComponent("installed.json").path,
                    isSystem: false)
            }
        }
    }
}

private final class BundleToken {}
