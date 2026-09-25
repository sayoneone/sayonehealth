// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SayoneCore",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v14)],
    products: [.library(name: "SayoneCore", targets: ["SayoneCore"])],
    targets: [
        .target(name: "SayoneCore"),
        .testTarget(name: "SayoneCoreTests", dependencies: ["SayoneCore"])
    ]
)
