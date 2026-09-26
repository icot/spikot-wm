// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift
// required to build this package.

import PackageDescription

let package = Package(
  name: "SpikotWM",
  platforms: [.macOS(.v26)],
  products: [
    .executable(name: "spikot-wm", targets: ["StateTool"]),
    .executable(name: "spikot-placer", targets: ["PlacerTool"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    .package(url: "https://github.com/apple/swift-log", from: "1.6.0"),
  ],
  targets: [
    .target(
      name: "StateCore",
      dependencies: [
        .product(name: "Logging", package: "swift-log"),
      ],
      path: "Sources/StateCore"),
    .executableTarget(
      name: "PlacerTool",
      dependencies: ["StateCore"],
      path: "Sources/Placer"),
    .executableTarget(
      name: "StateTool",
      dependencies: [
        "StateCore",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ],
      path: "Sources/State"),
  ]
)
