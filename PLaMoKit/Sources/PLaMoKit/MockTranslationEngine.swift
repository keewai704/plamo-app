import Foundation

/// Deterministic engine used by UI tests and by the simulator, where the
/// upstream llama.cpp xcframework has no simulator slice.
public struct MockTranslationEngine: TranslationEngine {
    public var delay: Duration
    public var failure: TranslationEngineError?

    public init(delay: Duration = .zero, failure: TranslationEngineError? = nil) {
        self.delay = delay
        self.failure = failure
    }

    public func translate(_ request: TranslationRequest) async throws -> String {
        if delay > .zero {
            try await Task.sleep(for: delay)
        }
        if let failure { throw failure }
        return "\(request.target.rawValue.uppercased()): \(request.text)"
    }
}
