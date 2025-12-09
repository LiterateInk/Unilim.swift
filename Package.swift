// swift-tools-version: 6.1
import PackageDescription

let package = Package(
  name: "Unilim",
  platforms: [
    .macOS(.v13),
    .iOS(.v16),
  ],
  products: [
    .library(name: "UnilimIUTCS", targets: ["UnilimIUTCS"]),
    .library(name: "UnilimIUT", targets: ["UnilimIUT"]),
    .library(name: "UnilimCAS", targets: ["UnilimCAS"]),
  ],
  dependencies: [
    .package(url: "https://github.com/Vexcited/Rikka", from: "0.1.0"),
    .package(url: "https://github.com/lachlanbell/SwiftOTP", from: "3.0.2"),
    .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.4.5"),
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
      name: "UnilimCAS",
      dependencies: ["Rikka", "SwiftOTP"]
    ),
  ]
)
