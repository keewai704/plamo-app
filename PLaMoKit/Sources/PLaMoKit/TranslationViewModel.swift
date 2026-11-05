import Foundation
import Observation

@MainActor
@Observable
public final class TranslationViewModel {
    public var input: String
    public var output: String = ""
    public var isTranslating: Bool = false
    public var errorMessage: String?
    public var targetLanguage: TranslationLanguage = .english
    public var form: OutputForm = .polite
    public private(set) var detectedSourceLanguage: TranslationLanguage?
    public private(set) var isTargetManuallySelected = false

    public init(input: String = "", targetLanguage: TranslationLanguage? = nil) {
        self.input = input
        if let targetLanguage {
            self.targetLanguage = targetLanguage
            self.isTargetManuallySelected = true
        }
    }

    public var trimmedInput: String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var canTranslate: Bool {
        !trimmedInput.isEmpty && !isTranslating
    }

    public func selectTarget(_ language: TranslationLanguage) {
        targetLanguage = language
        isTargetManuallySelected = true
    }

    /// Update the suggested target from the input, unless the user picked one.
    public func updateSuggestedTarget() {
        guard !isTargetManuallySelected else { return }
        let detected = LanguageDetector.detect(input)
        detectedSourceLanguage = detected
        targetLanguage = TranslationLanguage.suggestedTarget(for: detected)
    }

    public func translate(
        using engine: any TranslationEngine,
        maxCharacters: Int = TextChunker.defaultMaxCharacters
    ) async {
        guard canTranslate else { return }

        errorMessage = nil
        output = ""
        isTranslating = true
        defer { isTranslating = false }

        let source = LanguageDetector.detect(trimmedInput)
        detectedSourceLanguage = source

        let chunks = TextChunker.chunks(in: trimmedInput, maxCharacters: maxCharacters)
        guard !chunks.isEmpty else { return }

        var translatedChunks: [String] = []
        do {
            for chunk in chunks {
                try Task.checkCancellation()
                let request = TranslationRequest(
                    text: chunk,
                    target: targetLanguage,
                    source: nil,
                    form: targetLanguage == .japanese ? form : nil
                )
                let translated = try await engine.translate(request)
                translatedChunks.append(translated.trimmingCharacters(in: .whitespacesAndNewlines))
                output = translatedChunks.joined(separator: "\n")
            }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
