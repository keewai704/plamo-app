import Foundation
import NaturalLanguage

public enum LanguageDetector {
    /// Best-effort language detection. Used to pick the default target
    /// language, not to fill `source_lang` in the prompt.
    public static func detect(_ text: String) -> TranslationLanguage? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.count >= 4 {
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(trimmed)
            if let language = recognizer.dominantLanguage, let mapped = map(language) {
                return mapped
            }
        }
        return heuristic(trimmed)
    }

    /// NaturalLanguage is unreliable for very short strings, so fall back to
    /// script detection. Han-only text stays `nil` because Japanese and
    /// Chinese are ambiguous without kana.
    private static func heuristic(_ text: String) -> TranslationLanguage? {
        let scalars = text.unicodeScalars
        if scalars.contains(where: { (0x3040...0x30FF).contains($0.value) }) {
            return .japanese
        }
        if scalars.allSatisfy({ $0.isASCII }) {
            return .english
        }
        return nil
    }

    public static func map(_ language: NLLanguage) -> TranslationLanguage? {
        switch language {
        case .japanese: .japanese
        case .english: .english
        case .simplifiedChinese, .traditionalChinese: .simplifiedChinese
        case .korean: .korean
        case .french: .french
        case .german: .german
        case .spanish: .spanish
        case .portuguese: .portuguese
        case .italian: .italian
        case .russian: .russian
        case .arabic: .arabic
        default: nil
        }
    }
}
