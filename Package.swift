// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "Unilim",
  platforms: [
    .macOS(.v13),
    .iOS(.v15),
  ],
  products: [
    .library(name: "UnilimIUTCS", targets: ["UnilimIUTCS"]),
    .library(name: "UnilimIUT", targets: ["UnilimIUT"]),
    .library(name: "Unilim", targets: ["Unilim"]),
  ],
  targets: [
    .target(
      name: "UnilimIUTCS",
      linkerSettings: [
        .linkedFramework("CoreGraphics")
      ]
    ),
    .testTarget(
      name: "UnilimIUTCSTests", dependencies: ["UnilimIUTCS"], resources: [.copy("Resources")]),
    .target(
      name: "UnilimIUT",
    ),
    .target(
      name: "Unilim",
    ),
  ]
)
