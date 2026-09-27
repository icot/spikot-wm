// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift
// required to build this package.

import PackageDescription

let package = Package(
  name: "SpikotWM",
  platforms: [.macOS(.v26)],
  products: [
    .executable(name: "spikot-wm", targets: ["StateTool"]),
    .executable(name: "spikot-agent", targets: ["AgentTool"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    .package(url: "https://github.com/apple/swift-log", from: "1.6.0"),
  ],
  targets: [
    // Declares the private _AXUIElementGetWindow, which has no public header.
    .target(
      name: "CSpikotAX",
      path: "Sources/CSpikotAX"),
    // Accessibility: window identity, geometry and permission.
    .target(
      name: "SpikotAX",
      dependencies: [
        "CSpikotAX",
        .product(name: "Logging", package: "swift-log"),
      ],
      path: "Sources/SpikotAX"),
    .target(
      name: "StateCore",
      dependencies: [
        "SpikotAX",
        .product(name: "Logging", package: "swift-log"),
      ],
      path: "Sources/StateCore"),
    .testTarget(
      name: "StateCoreTests",
      dependencies: ["StateCore", "SpikotAX", "CSpikotAX"],
      path: "Tests/StateCoreTests"),
    .executableTarget(
      name: "AgentTool",
      dependencies: [
        "StateCore",
        "SpikotAX",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ],
      path: "Sources/Agent"),
    .executableTarget(
      name: "StateTool",
      dependencies: [
        "StateCore",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ],
      path: "Sources/State"),
  ]
)
