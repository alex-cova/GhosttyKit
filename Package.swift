// swift-tools-version: 6.0

import Foundation
import PackageDescription

let kitPath = "Vendor/GhosttyKit.xcframework"
let hasGhosttyKit = FileManager.default.fileExists(atPath: kitPath)

let ghosttyUISettings: [SwiftSetting] = hasGhosttyKit
    ? [.swiftLanguageMode(.v6), .define("GHOSTTYUI_HAS_KIT")]
    : [.swiftLanguageMode(.v6)]

var packageTargets: [Target] = [
    .target(
        name: "GhosttyUI",
        dependencies: hasGhosttyKit ? ["GhosttyKit"] : [],
        swiftSettings: ghosttyUISettings
    ),
    .testTarget(
        name: "GhosttyUITests",
        dependencies: ["GhosttyUI"],
        swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .executableTarget(
        name: "GhosttyUIDemo",
        dependencies: ["GhosttyUI"],
        path: "Examples/GhosttyUIDemo",
        swiftSettings: ghosttyUISettings
    )
]

if hasGhosttyKit {
    packageTargets.insert(
        .binaryTarget(name: "GhosttyKit", path: kitPath),
        at: 0
    )
}

let package = Package(
    name: "GhosttyUI",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "GhosttyUI", targets: ["GhosttyUI"]),
        .executable(name: "GhosttyUIDemo", targets: ["GhosttyUIDemo"])
    ],
    targets: packageTargets
)
