import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@main
@MainActor
struct KotobaApp: App {
    @State private var model = AppModel()

    init() {
        #if canImport(UIKit)
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
            UIView.setAnimationsEnabled(false)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task { await model.start() }
        }
    }
}
