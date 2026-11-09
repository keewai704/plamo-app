import Foundation

public enum Languages {
    /// Selects the model's own switching between Japanese and English.
    public static let auto = "auto"

    /// The model's language codes. The browser extension reads the same file.
    public static let codes: [String] = {
        guard
            let url = Bundle.module.url(forResource: "languages", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let codes = try? JSONDecoder().decode([String].self, from: data)
        else {
            preconditionFailure("languages.json is missing from the KotobaCore bundle")
        }
        return codes
    }()

    public static func displayName(for code: String, locale: Locale = .current) -> String {
        locale.localizedString(forIdentifier: code) ?? code
    }
}
