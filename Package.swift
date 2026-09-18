// swift-tools-version: 6.0

import Foundation
import PackageDescription

let kitRelativePath = "Vendor/GhosttyKit.xcframework"
let packageDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let kitAbsolutePath = "\(packageDirectory)/\(kitRelativePath)"
let hasGhosttyKit = FileManager.default.fileExists(atPath: kitAbsolutePath)

let ghosttyKitSettings: [SwiftSetting] = hasGhosttyKit
    ? [.swiftLanguageMode(.v6), .define("GHOSTTYKIT_HAS_KIT")]
    : [.swiftLanguageMode(.v6)]

// libghostty-fat.a is static; SwiftPM must link its Apple/C++ dependencies too.
let ghosttyKitLinkerSettings: [LinkerSetting] = hasGhosttyKit
    ? [
        .linkedLibrary("c++"),
        .linkedFramework("Carbon"),
        .linkedFramework("CoreFoundation"),
        .linkedFramework("CoreGraphics"),
        .linkedFramework("CoreText"),
        .linkedFramework("CoreVideo"),
        .linkedFramework("IOSurface"),
        .linkedFramework("QuartzCore"),
    ]
    : []

var packageTargets: [Target] = [
    .target(
        name: "GhosttyKit",
        dependencies: hasGhosttyKit ? ["GhosttyKitXCFramework"] : [],
        swiftSettings: ghosttyKitSettings,
        linkerSettings: ghosttyKitLinkerSettings
    ),
    .testTarget(
        name: "GhosttyKitTests",
        dependencies: ["GhosttyKit"],
        swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .executableTarget(
        name: "GhosttyKitDemo",
        dependencies: ["GhosttyKit"],
        path: "Examples/GhosttyKitDemo",
        swiftSettings: ghosttyKitSettings
    )
]

if hasGhosttyKit {
    packageTargets.insert(
        .binaryTarget(name: "GhosttyKitXCFramework", path: kitRelativePath),
        at: 0
    )
}

let package = Package(
    name: "GhosttyKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "GhosttyKit", targets: ["GhosttyKit"]),
        .executable(name: "GhosttyKitDemo", targets: ["GhosttyKitDemo"])
    ],
    targets: packageTargets
)
