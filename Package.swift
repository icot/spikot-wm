// swift-tools-version: 5.7.3
// The swift-tools-version declares the minimum version of Swift
// required to build this package.

import PackageDescription

let package = Package(
  name: "SpikotWM",
  platforms:[.macOS(.v13)],
  products:[
    .executable(name: "spikot-state", targets:["State"]),
    .executable(name: "spikot-placer", targets:["Placer"]),
  ],
  dependencies: [],
  targets: [
    .executableTarget(
      name: "State",
      dependencies: [],
      path: "Sources/State")
  ,
    .executableTarget(
      name: "Placer",
      dependencies: ["State"],
      path: "Sources/Placer"),
    ]
)
