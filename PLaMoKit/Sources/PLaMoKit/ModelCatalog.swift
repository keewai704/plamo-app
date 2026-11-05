import Foundation

public struct ModelVariant: Identifiable, Hashable, Sendable {
    public var fileName: String
    public var quantization: String
    public var approximateBytes: Int64
    public var downloadURL: URL
    public var isRecommended: Bool

    public var id: String { fileName }

    public init(
        fileName: String,
        quantization: String,
        approximateBytes: Int64,
        downloadURL: URL,
        isRecommended: Bool = false
    ) {
        self.fileName = fileName
        self.quantization = quantization
        self.approximateBytes = approximateBytes
        self.downloadURL = downloadURL
        self.isRecommended = isRecommended
    }

    public var displayName: String { "PLaMo 3 Translate 0.8B / \(quantization)" }

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: approximateBytes, countStyle: .file)
    }

    /// Needed for the PLaMo Community License attribution requirement.
    public var modelIdentifier: String { "plamo-3-translate-0.8b-\(quantization)" }
}

public enum ModelCatalog {
    public static let repository = "pfnet/plamo-3-translate-0.8b-GGUF"
    public static let licenseURL = URL(string: "https://plamo.preferredai.jp/info/plamo-community-license-ja")!
    public static let modelPageURL = URL(string: "https://huggingface.co/pfnet/plamo-3-translate-0.8b-GGUF")!

    private static let baseURL = URL(string: "https://huggingface.co/\(repository)/resolve/main/")!

    public static let variants: [ModelVariant] = [
        ModelVariant(
            fileName: "plamo-3-translate-0.8b-Q2_K.gguf",
            quantization: "Q2_K",
            approximateBytes: 410_000_000,
            downloadURL: baseURL.appendingPathComponent("plamo-3-translate-0.8b-Q2_K.gguf"),
            isRecommended: false
        ),
        ModelVariant(
            fileName: "plamo-3-translate-0.8b-Q3_K_M.gguf",
            quantization: "Q3_K_M",
            approximateBytes: 486_000_000,
            downloadURL: baseURL.appendingPathComponent("plamo-3-translate-0.8b-Q3_K_M.gguf"),
            isRecommended: true
        ),
        ModelVariant(
            fileName: "plamo-3-translate-0.8b-Q4_K_M.gguf",
            quantization: "Q4_K_M",
            approximateBytes: 573_000_000,
            downloadURL: baseURL.appendingPathComponent("plamo-3-translate-0.8b-Q4_K_M.gguf"),
            isRecommended: false
        ),
    ]

    public static var recommended: ModelVariant {
        variants.first(where: \.isRecommended) ?? variants[1]
    }
}
