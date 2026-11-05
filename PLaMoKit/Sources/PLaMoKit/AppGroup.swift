import Foundation

/// App Group used to share the downloaded GGUF between the app and the
/// Translation UI Provider extension.
///
/// Keep this value in sync with:
///   - PLaMoTranslate/PLaMoTranslate.entitlements
///   - PLaMoTranslateExtension/PLaMoTranslateExtension.entitlements
///   - project.yml (bundle identifiers)
public enum AppGroup {
    public static let identifier = "group.jp.keewai.kotoba"

    /// The shared container, or `nil` when the entitlement is unavailable
    /// (simulator without signing, unit tests, etc).
    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}
