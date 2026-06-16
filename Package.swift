// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Lexicon",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Lexicon",
            path: "Sources/Lexicon"
        )
    ]
)
