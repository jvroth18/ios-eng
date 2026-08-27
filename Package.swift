// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "ios-eng",
  platforms: [
    .iOS(.v18),
    .macOS(.v15),
  ],
  products: [
    .library(name: "EngCore", targets: ["EngCore"])
  ],
  targets: [
    .target(name: "EngCore"),
    .testTarget(name: "EngCoreTests", dependencies: ["EngCore"]),
  ]
)
