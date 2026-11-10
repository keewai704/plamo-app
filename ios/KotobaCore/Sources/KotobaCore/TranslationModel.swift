import Foundation
import Observation

@MainActor
@Observable
public final class TranslationModel {
    public var input = ""
    public private(set) var output = ""
    public private(set) var errorMessage: String?
    public private(set) var isTranslating = false

    private var task: Task<Void, Never>?

    public init() {}

    public var canTranslate: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Starts translating, replacing any earlier result. Long text appears chunk by chunk.
    public func translate(using client: TranslationClient, target: String, form: OutputForm?) {
        task?.cancel()
        let chunks = TextChunker.chunks(in: input)
        guard !chunks.isEmpty else { return }

        output = ""
        errorMessage = nil
        isTranslating = true
        task = Task {
            do {
                for chunk in chunks {
                    let translated = try await client.translate(chunk, target: target, form: form)
                    try Task.checkCancellation()
                    output += output.isEmpty ? translated : "\n" + translated
                }
            } catch {
                // A newer request or the stop button took over and owns the state now.
                if Task.isCancelled { return }
                errorMessage = error.localizedDescription
            }
            isTranslating = false
        }
    }

    public func cancel() {
        task?.cancel()
        task = nil
        isTranslating = false
    }

    /// Waits for the running translation; lets tests observe the outcome.
    public func waitUntilFinished() async {
        await task?.value
    }
}
