import ExtensionKit
import Foundation
import os

let logger = Logger(subsystem: "jp.keewai.kotoba", category: "TranslationProvider")
logger.info("Starting translation provider")

try TranslationProviderExtension.main()
