// swift-tools-version: 6.2
// 内置副本：只保留 TourKit library（上游另有 TourKitSampleApp、TourKitTests），见 VENDORED.md

import PackageDescription

let package = Package(
    name: "TourKit",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "TourKit",
            targets: ["TourKit"]
        ),
    ],
    targets: [
        .target(
            name: "TourKit"
        ),
    ]
)
