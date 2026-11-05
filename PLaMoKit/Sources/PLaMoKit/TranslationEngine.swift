import Foundation

public protocol TranslationEngine: Sendable {
    func translate(_ request: TranslationRequest) async throws -> String
}

public struct EngineOptions: Sendable, Equatable {
    public var contextLength: Int
    public var batchSize: Int
    public var microBatchSize: Int
    /// 0 means "pick a sensible value for this device".
    public var threadCount: Int
    public var gpuLayers: Int
    public var maxNewTokens: Int

    public init(
        contextLength: Int,
        batchSize: Int,
        microBatchSize: Int,
        threadCount: Int = 0,
        gpuLayers: Int = 999,
        maxNewTokens: Int = 512
    ) {
        self.contextLength = contextLength
        self.batchSize = batchSize
        self.microBatchSize = microBatchSize
        self.threadCount = threadCount
        self.gpuLayers = gpuLayers
        self.maxNewTokens = maxNewTokens
    }

    public var resolvedThreadCount: Int {
        if threadCount > 0 { return threadCount }
        return max(1, min(6, ProcessInfo.processInfo.activeProcessorCount - 1))
    }

    /// Foreground app: 2k context, q8 KV cache, Metal offload.
    public static let appDefault = EngineOptions(
        contextLength: 2_048,
        batchSize: 256,
        microBatchSize: 128,
        maxNewTokens: 512
    )

    /// Extension: smaller footprint, called from a short-lived process.
    public static let translationExtension = EngineOptions(
        contextLength: 1_024,
        batchSize: 128,
        microBatchSize: 64,
        maxNewTokens: 384
    )
}

public enum TranslationEngineError: LocalizedError, Equatable {
    case unsupportedPlatform
    case modelMissing(String)
    case modelLoadFailed(String)
    case contextCreationFailed
    case samplerCreationFailed
    case tokenizationFailed
    case inputTooLong
    case decodeFailed(Int32)

    public var errorDescription: String? {
        switch self {
        case .unsupportedPlatform:
            "この端末では llama.cpp を利用できません。"
        case let .modelMissing(name):
            "モデルが見つかりません: \(name)"
        case let .modelLoadFailed(name):
            "モデルを読み込めませんでした: \(name)"
        case .contextCreationFailed:
            "推論コンテキストを作成できませんでした。"
        case .samplerCreationFailed:
            "サンプラーを作成できませんでした。"
        case .tokenizationFailed:
            "入力をトークン化できませんでした。"
        case .inputTooLong:
            "入力が長すぎます。文章を分割してください。"
        case let .decodeFailed(code):
            "推論に失敗しました (code: \(code))。"
        }
    }
}
