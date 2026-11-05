// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PLaMoKit",
    platforms: [
        .iOS("18.4"),
        .macOS("15.0"),
    ],
    products: [
        .library(name: "PLaMoKit", targets: ["PLaMoKit"]),
    ],
    targets: [
        .target(
            name: "PLaMoKit",
            path: "Sources/PLaMoKit"
        ),
    ],
    swiftLanguageVersions: [.v5]
)
