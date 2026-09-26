// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ShiftZones",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ShiftZones", targets: ["ShiftZones"]),
    ],
    targets: [
        // Pure logic (model, geometry, layout templates, editing): no AppKit dependency.
        .target(name: "ShiftZonesCore"),
        // Menu bar app: Accessibility, overlay, editor, settings.
        .executableTarget(name: "ShiftZones", dependencies: ["ShiftZonesCore"]),
        // Checks for the core logic (`swift run CoreChecks`): XCTest isn't available without Xcode.
        .executableTarget(name: "CoreChecks", dependencies: ["ShiftZonesCore"], path: "Tests/CoreChecks"),
    ]
)
