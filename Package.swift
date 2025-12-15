// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AFMServer",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "afm-server", targets: ["AFMServer"])
    ],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "AFMServer",
            dependencies: [
                .product(name: "Hummingbird", package: "hummingbird"),
            ]
        )
    ]
)
