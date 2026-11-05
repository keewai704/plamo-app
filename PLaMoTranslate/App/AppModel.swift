import Foundation
import Observation
import PLaMoKit

@MainActor
@Observable
final class AppModel {
    enum EngineState: Equatable {
        case noModel
        case loading
        case ready
        case failed(String)
    }

    var translation = TranslationViewModel()
    var engineState: EngineState = .noModel
    var installedVariant: ModelVariant?
    var installedVariantIDs: Set<ModelVariant.ID> = []
    var isUsingMockEngine = false
    var isShowingModelSheet = false
    var downloadProgress: Double?
    var downloadingVariant: ModelVariant?
    var errorMessage: String?

    let isUITesting: Bool
    private let store: ModelStore
    private let downloader = ModelDownloader()
    private var engine: (any TranslationEngine)?

    init(store: ModelStore = .shared()) {
        self.store = store
        self.isUITesting = ProcessInfo.processInfo.arguments.contains("-ui-testing")
        self.installedVariantIDs = Set(store.installedVariants().map(\.id))
    }

    var modelVariants: [ModelVariant] { ModelCatalog.variants }

    func isInstalled(_ variant: ModelVariant) -> Bool {
        installedVariantIDs.contains(variant.id)
    }

    func refreshInstalledVariants() {
        installedVariantIDs = Set(store.installedVariants().map(\.id))
    }

    func isDownloading(_ variant: ModelVariant) -> Bool {
        downloadingVariant == variant
    }

    func start() async {
        guard engine == nil else { return }

        if isUITesting {
            useMockEngine()
            return
        }
        if !LlamaEngine.isSupported {
            useMockEngine()
            return
        }
        await loadEngine()
    }

    func loadEngine() async {
        engine = nil
        isUsingMockEngine = false

        guard LlamaEngine.isSupported else {
            useMockEngine()
            return
        }
        guard let variant = store.preferredInstalledVariant() else {
            installedVariant = nil
            engineState = .noModel
            return
        }

        engineState = .loading
        let url = store.url(for: variant)
        do {
            let newEngine = try await Task.detached(priority: .userInitiated) {
                try LlamaEngine(modelURL: url, options: .appDefault)
            }.value
            engine = newEngine
            installedVariant = variant
            engineState = .ready
        } catch {
            engineState = .failed(error.localizedDescription)
        }
    }

    func translate() async {
        guard let engine else { return }
        await translation.translate(using: engine)
    }

    func download(_ variant: ModelVariant) {
        guard downloadProgress == nil else { return }
        downloadProgress = 0
        downloadingVariant = variant

        Task {
            do {
                let temporaryURL = try await downloader.download(variant) { [weak self] value in
                    Task { @MainActor in
                        self?.downloadProgress = value
                    }
                }
                try store.install(temporaryURL, as: variant)
                downloadProgress = nil
                downloadingVariant = nil
                refreshInstalledVariants()
                await loadEngine()
            } catch {
                downloadProgress = nil
                downloadingVariant = nil
                errorMessage = error.localizedDescription
            }
        }
    }

    func importModel(from url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }

        do {
            let variant = ModelCatalog.recommended
            let temporaryURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("kotoba-import-\(UUID().uuidString).gguf")
            try FileManager.default.copyItem(at: url, to: temporaryURL)
            try store.install(temporaryURL, as: variant)
            refreshInstalledVariants()
            Task { await loadEngine() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ variant: ModelVariant) {
        do {
            try store.remove(variant)
            refreshInstalledVariants()
            if installedVariant == variant {
                Task { await loadEngine() }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func useMockEngine() {
        engine = MockTranslationEngine(delay: .milliseconds(80))
        installedVariant = nil
        isUsingMockEngine = true
        engineState = .ready
    }
}
