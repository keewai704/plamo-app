import ExtensionKit
import SwiftUI
import TranslationUIProvider

@MainActor
final class TranslationProviderExtension: TranslationUIProviderExtension {
    required init() {}

    var body: some TranslationUIProviderExtensionScene {
        TranslationUIProviderSelectedTextScene { context in
            TranslationProviderView(context: context)
        }
    }
}
