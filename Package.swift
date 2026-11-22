// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Poise",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Poise", targets: ["Poise"])],
    targets: [
        .target(name: "PoiseCore"),
        .executableTarget(name: "Poise", dependencies: ["PoiseCore"]),
        .testTarget(name: "PoiseCoreTests", dependencies: ["PoiseCore"])
    ]
)
