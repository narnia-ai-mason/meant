// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "Meant",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .library(name: "MeantCore", targets: ["MeantCore"]),
    .executable(name: "MeantApp", targets: ["MeantApp"]),
  ],
  targets: [
    .target(
      name: "MeantCore",
      resources: [
        .copy("Resources/english.txt"),
      ]
    ),
    .executableTarget(
      name: "MeantApp",
      dependencies: ["MeantCore"],
      exclude: ["Info.plist"]
    ),
    .testTarget(
      name: "MeantCoreTests",
      dependencies: ["MeantCore"]
    ),
  ]
)
