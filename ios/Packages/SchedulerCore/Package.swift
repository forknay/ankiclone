// swift-tools-version: 5.10
import PackageDescription

let package = Package(
  name: "SchedulerCore",
  platforms: [.iOS(.v17), .macOS(.v14)],
  products: [.library(name: "SchedulerCore", targets: ["SchedulerCore"])],
  dependencies: [
    // Pinned to an exact commit: this code decides when every card comes back.
    .package(url: "https://github.com/4rays/swift-fsrs", revision: "6779d34a76c90d8a9be9aa13724365d951f6f819")
  ],
  targets: [
    .target(name: "SchedulerCore", dependencies: [.product(name: "SwiftFSRS", package: "swift-fsrs")]),
    .testTarget(name: "SchedulerCoreTests", dependencies: ["SchedulerCore"]),
  ]
)
