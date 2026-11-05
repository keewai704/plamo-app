import Foundation

/// Languages supported by the PLaMo 3 Translate prompt format.
///
/// The code is the value used for `<|plamo:val|>` in PFML3 prompts. The
/// template requires lowercase, region-less codes (plus the special
/// `ja(easy)` form, which this app does not expose yet).
public enum TranslationLanguage: String, CaseIterable, Codable, Sendable, Identifiable {
    case japanese = "ja"
    case english = "en"
    case simplifiedChinese = "zh-hans"
    case korean = "ko"
    case french = "fr"
    case german = "de"
    case spanish = "es"
    case portuguese = "pt"
    case italian = "it"
    case russian = "ru"
    case arabic = "ar"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .japanese: "日本語"
        case .english: "英語"
        case .simplifiedChinese: "中国語（簡体）"
        case .korean: "韓国語"
        case .french: "フランス語"
        case .german: "ドイツ語"
        case .spanish: "スペイン語"
        case .portuguese: "ポルトガル語"
        case .italian: "イタリア語"
        case .russian: "ロシア語"
        case .arabic: "アラビア語"
        }
    }

    /// Japanese source text translates to English, everything else defaults
    /// to Japanese. This is only a suggestion; the user can always override.
    public static func suggestedTarget(for source: TranslationLanguage?) -> TranslationLanguage {
        guard let source else { return .english }
        return source == .japanese ? .english : .japanese
    }

    public static func defaultTarget(for source: TranslationLanguage) -> TranslationLanguage {
        suggestedTarget(for: source)
    }

    /// PFML3 expects lowercase language codes without region subtags.
    public var isValidPromptCode: Bool {
        let pattern = #"^[a-z]{2,3}(-[a-z]{4})?$"#
        return rawValue.range(of: pattern, options: .regularExpression) != nil
    }
}

/// Tone of the output. Only valid when the target language is Japanese.
public enum OutputForm: String, CaseIterable, Codable, Sendable {
    case polite
    case plain

    public var displayName: String {
        switch self {
        case .polite: "敬体"
        case .plain: "常体"
        }
    }
}
