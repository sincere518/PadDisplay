// swift-tools-version: 6.1
// 源自 https://github.com/jaywcjlove/PermissionFlow v2.11.3（MIT），仅保留 PermissionFlow 与 SystemSettingsKit
import PackageDescription

let package = Package(
    name: "PermissionFlow",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "SystemSettingsKit", targets: ["SystemSettingsKit"]),
        .library(name: "PermissionFlow", targets: ["PermissionFlow"]),
    ],
    targets: [
        .target(name: "SystemSettingsKit"),
        .target(name: "PermissionFlow", dependencies: ["SystemSettingsKit"], resources: [.process("Resources")]),
    ]
)
