// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "KotobaCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "KotobaCore", targets: ["KotobaCore"])],
    targets: [
        .target(name: "KotobaCore", resources: [.copy("Resources/languages.json")]),
        .testTarget(name: "KotobaCoreTests", dependencies: ["KotobaCore"]),
    ]
)
