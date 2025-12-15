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
    targets: [
        .executableTarget(name: "AFMServer")
    ]
)
