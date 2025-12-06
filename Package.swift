// swift-tools-version: 5.7.3
// The swift-tools-version declares the minimum version of Swift
// required to build this package.

import PackageDescription

let package = Package(
  name: "SpikotWM",
  platforms:[.macOS(.v13)],
  products:[
    .executable(name: "spikot-wm", targets:["StateTool"]),
    .executable(name: "spikot-placer", targets:["PlacerTool"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
  ],
  targets: [
    .target(
      name: "StateCore",
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
        path: "Sources/State")
  ]
)
