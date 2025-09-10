// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "Pawnilim",
  platforms: [
    .macOS(.v13),
    .iOS(.v15),
  ],
  products: [
    .library(name: "PawnilimIUTCS", targets: ["PawnilimIUTCS"]),
    .library(name: "PawnilimIUT", targets: ["PawnilimIUT"]),
    .library(name: "Pawnilim", targets: ["Pawnilim"]),
  ],
  targets: [
    .target(
      name: "PawnilimIUTCS",
      linkerSettings: [
        .linkedFramework("CoreGraphics")
      ]
    ),
    .testTarget(
      name: "PawnilimIUTCSTests", dependencies: ["PawnilimIUTCS"], resources: [.copy("Resources")]),
    .target(
      name: "PawnilimIUT",
    ),
    .target(
      name: "Pawnilim",
    ),
  ]
)
