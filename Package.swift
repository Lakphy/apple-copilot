// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AppleCopilot",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "CopilotCore", targets: ["CopilotCore"]),
        .library(name: "CopilotUI", targets: ["CopilotUI"]),
        .library(name: "MacIntegration", targets: ["MacIntegration"]),
        .executable(name: "AppleCopilotMac", targets: ["AppleCopilotApp"])
    ],
    targets: [
        .target(name: "CopilotCore"),
        .target(name: "CopilotUI", dependencies: ["CopilotCore"]),
        .target(name: "MacIntegration", dependencies: ["CopilotUI", "CopilotCore"]),
        .executableTarget(name: "AppleCopilotApp", dependencies: ["CopilotUI", "CopilotCore", "MacIntegration"]),
        .testTarget(name: "CopilotCoreTests", dependencies: ["CopilotCore"])
    ],
    swiftLanguageModes: [.v6]
)
