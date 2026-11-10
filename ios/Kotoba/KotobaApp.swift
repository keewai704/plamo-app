import SwiftUI

@main
struct KotobaApp: App {
    var body: some Scene {
        WindowGroup {
            TranslateView()
        }
    }
}

/// Keys shared by the `@AppStorage` properties. Launch arguments such as
/// `-serverURL http://…` override them, which is how the UI tests pick a server.
enum StorageKey {
    static let serverURL = "serverURL"
    static let target = "target"
    static let form = "form"
}
