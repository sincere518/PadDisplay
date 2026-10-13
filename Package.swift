// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PadDisplay",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "PadDisplay", targets: ["PadDisplay"])],
    targets: [
        .target(name: "PadDisplayCore"),
        .target(name: "DisplayBridge", cSettings: [.unsafeFlags(["-fobjc-arc"])],
                linkerSettings: [.linkedFramework("CoreGraphics")]),
        .executableTarget(name: "PadDisplay", dependencies: ["PadDisplayCore", "DisplayBridge"]),
    ]
)
