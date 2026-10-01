// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Nocturne",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Nocturne", targets: ["Nocturne"])
    ],
    targets: [
        .executableTarget(
            name: "Nocturne",
            path: "Sources/Nocturne",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
