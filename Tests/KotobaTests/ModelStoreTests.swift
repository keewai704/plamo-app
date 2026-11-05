import XCTest
import PLaMoKit

final class ModelStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kotoba-model-store-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    func testInstallDetectsAndRemovesModel() throws {
        let store = ModelStore(directory: directory)
        let variant = ModelCatalog.recommended
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).gguf")
        try Data("GGUF".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }

        XCTAssertTrue(store.installedVariants().isEmpty)
        try store.install(source, as: variant)

        XCTAssertEqual(store.installedVariants(), [variant])
        XCTAssertEqual(store.preferredInstalledVariant(), variant)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url(for: variant).path))

        try store.remove(variant)
        XCTAssertTrue(store.installedVariants().isEmpty)
    }

    func testInstallReplacesExistingFile() throws {
        let store = ModelStore(directory: directory)
        let variant = ModelCatalog.variants[0]

        for contents in ["first", "second"] {
            let source = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString).gguf")
            try Data(contents.utf8).write(to: source)
            try store.install(source, as: variant)
        }

        let data = try Data(contentsOf: store.url(for: variant))
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "second")
    }
}
