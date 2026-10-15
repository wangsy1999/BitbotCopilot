// swift-tools-version: 5.9
// Copyright (c) 2026 Siyuan Wang.
// Licensed under the GNU General Public License v3. See LICENSE.

import PackageDescription

let package = Package(
    name: "BitbotCopilot",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "BitbotCopilot", targets: ["BitbotCopilot"])],
    targets: [
        .target(name: "BitbotCore", path: "macOS/Sources/BitbotCore"),
        .executableTarget(name: "BitbotCopilot", dependencies: ["BitbotCore"], path: "macOS/Sources/BitbotCopilot", resources: [.copy("Resources/AppIcon.icns"), .copy("Resources/Legal")]),
        .testTarget(name: "BitbotAppTests", dependencies: ["BitbotCopilot", "BitbotCore"], path: "macOS/Tests/BitbotAppTests"),
        .testTarget(name: "BitbotCoreTests", dependencies: ["BitbotCore"], path: "macOS/Tests/BitbotCoreTests", resources: [.copy("Fixtures")])
    ]
)
