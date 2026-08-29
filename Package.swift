// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "ios-eng",
  platforms: [
    .iOS("18.0"),
    .macOS("15.0"),
  ],
  products: [
    .library(name: "EngCore", targets: ["EngCore"]),
    .library(name: "EngBridgeCore", targets: ["EngBridgeCore"]),
    .library(name: "EngRelayCore", targets: ["EngRelayCore"]),
    .executable(name: "eng-bridge", targets: ["EngBridge"]),
  ],
  targets: [
    .target(name: "EngCore"),
    .target(name: "EngRelayCore", dependencies: ["EngCore"]),
    .target(name: "EngBridgeCore", dependencies: ["EngCore"]),
    .executableTarget(name: "EngBridge", dependencies: ["EngBridgeCore", "EngCore"]),
    .testTarget(name: "EngCoreTests", dependencies: ["EngCore"]),
    .testTarget(
      name: "EngBridgeCoreTests",
      dependencies: ["EngBridgeCore", "EngCore"]
    ),
    .testTarget(name: "EngRelayCoreTests", dependencies: ["EngRelayCore", "EngCore"]),
  ]
)
