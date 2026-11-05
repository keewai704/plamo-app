import Foundation

/// Owns GGUF files on disk. In the app and the extension this points at the
/// shared App Group container, so both processes mmap the same file.
public struct ModelStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static func shared() -> ModelStore {
        if let container = AppGroup.containerURL {
            return ModelStore(directory: container.appendingPathComponent("Models", isDirectory: true))
        }
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return ModelStore(directory: support.appendingPathComponent("Models", isDirectory: true))
    }

    public func url(for variant: ModelVariant) -> URL {
        directory.appendingPathComponent(variant.fileName, isDirectory: false)
    }

    public func installedVariants() -> [ModelVariant] {
        ModelCatalog.variants.filter { variant in
            FileManager.default.fileExists(atPath: url(for: variant).path)
        }
    }

    public func preferredInstalledVariant() -> ModelVariant? {
        let installed = installedVariants()
        return installed.first(where: \.isRecommended) ?? installed.first
    }

    public func install(_ sourceURL: URL, as variant: ModelVariant) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = url(for: variant)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        do {
            try fileManager.moveItem(at: sourceURL, to: destination)
        } catch {
            try fileManager.copyItem(at: sourceURL, to: destination)
        }
    }

    public func remove(_ variant: ModelVariant) throws {
        let destination = url(for: variant)
        guard FileManager.default.fileExists(atPath: destination.path) else { return }
        try FileManager.default.removeItem(at: destination)
    }
}
